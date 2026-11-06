#scope_module

require_task :: (session: *Session, task: *Task) {
	if task.phase != .READY || !task.optional {
		return;
	}


	for session.optional_ready {
		if it == task {
			remove it;
		}
	}

	task.optional = false;
	array_add(*session.ready, task);
}

monotonic_now :: (service: *Service) -> u64 {
	nanoseconds, representable := to_nanoseconds(current_time_monotonic() - service.clock_base);
	return ifx representable && nanoseconds >= 0
		then xx nanoseconds
		else U64_MAX;
}

enter_call :: (service: *Service, handle: Handle($K)) -> *Session {
	return enter_owner(service, handle.owner_service, handle.owner_token);
}

enter_owner :: (service: *Service, owner_service: *void, owner_token: u64) -> *Session {
	if owner_service != service || !owner_token {
		return null;
	}


	lock(*service.directory);
	session: *Session;
	for service.sessions {
		if it.registry.owner_token == owner_token {
			session = it;
			break;
		}
	}
	if session {
		session.call_pins += 1;
	}

	unlock(*service.directory);
	if session {
		lock(*session.gate);
	}

	return session;
}

leave_call :: (session: *Session) {
	if !session {
		return;
	}


	wake_all(*session.changed);
	retiring := session.retiring;
	unlock(*session.gate);
	cleanup_owned(session);
	service := session.service;
	lock(*service.directory);
	session.call_pins -= 1;
	session.directory_retiring ||= retiring;
	reclaim := session.directory_retiring && !session.call_pins;
	if reclaim {
		for service.sessions {
			if it == session {
				remove it;
			}
		}
	}

	unlock(*service.directory);
	if reclaim {
		push_allocator(owner_allocator(session));
		if session.threaded {
			thread_is_done(*session.reaper, -1);
			thread_deinit(*session.reaper);
		}

		destroy_session(session);
	}
}

wait_changed :: (session: *Session, remaining: u64) {
	milliseconds := min(remaining / 1_000_000, 1000).(s32);
	if remaining % 1_000_000 && milliseconds < 1000 {
		milliseconds += 1;
	}

	#if OS == .WINDOWS {
		cvariable_wait(*session.changed.condition_variable, *session.gate.csection, milliseconds);
	} else {
		end: timespec;
		clock_gettime(.REALTIME, *end);
		end.tv_nsec += milliseconds * 1_000_000;
		end.tv_sec += end.tv_nsec / 1_000_000_000;
		end.tv_nsec %= 1_000_000_000;
		pthread_cond_timedwait(*session.changed.condition_variable, *session.gate.csection, *end);
	}
}

start_workers :: (session: *Session) -> bool {
	#if TEST_HOOKS && !REAL_WORKER {
		return true;
	}

	session.threaded = true;
	session.compute.data = session;
	session.reaper.data = session;
	if !thread_init(*session.compute, compute_job, name = "Jai syntax worker") {
		return false;
	}

	if !thread_init(*session.reaper, reaper_job, name = "Jai syntax reaper") {
		session.lifecycle = .DRAINING;
		thread_start(*session.compute);
		thread_is_done(*session.compute, -1);
		thread_deinit(*session.compute);
		return false;
	}

	thread_start(*session.compute);
	thread_start(*session.reaper);
	return true;
}

compute_job :: (thread: *Thread) -> s64 {
	session := thread.data.(*Session);
	push_allocator(owner_allocator(session));
	lock(*session.gate);
	while session.lifecycle == .OPEN {
		mailbox := select_task(session);
		if !mailbox {
			wait(*session.changed, *session.gate);
			continue;
		}

		unlock(*session.gate);
		#if TEST_HOOKS {
			worker_pause(session, .SELECTED);
		}

		compute_task(session, mailbox);
		#if TEST_HOOKS {
			worker_pause(session, .PUBLICATION);
		}

		lock(*session.gate);
		deliver_mailbox(session, mailbox);
		wake_all(*session.changed);
		unlock(*session.gate);
		cleanup_owned(session);
		reset_temporary_storage();
		lock(*session.gate);
	}

	unlock(*session.gate);
	return 0;
}

stop_requested :: (session: *Session, task: *Task) -> bool {
	if session.threaded {
		lock(*session.gate);
	}

	stopped := task.phase == .STOP_REQUESTED;
	if session.threaded {
		unlock(*session.gate);
	}

	return stopped;
}

reaper_job :: (thread: *Thread) -> s64 {
	session := thread.data.(*Session);
	push_allocator(owner_allocator(session));
	lock(*session.gate);
	while session.lifecycle == .OPEN {
		wait(*session.changed, *session.gate);
	}

	unlock(*session.gate);
	thread_is_done(*session.compute, -1);
	thread_deinit(*session.compute);
	lock(*session.gate);
	session.worker_joined = true;
	while session.active_admissions {
		wait(*session.changed, *session.gate);
	}

	unlock(*session.gate);
	cleanup_owned(session);
	lock(*session.gate);
	while session.cleanup_pins {
		wait(*session.changed, *session.gate);
	}

	check_stopped(session);
	wake_all(*session.changed);
	unlock(*session.gate);
	return 0;
}

cleanup_owned :: (session: *Session) {
	push_allocator(owner_allocator(session));
	lock(*session.gate);
	worlds := session.retired_worlds;
	outputs := session.retired_outputs;
	sources := session.retired_sources;
	if !worlds.count && !outputs.count && !sources.count {
		check_stopped(session);
		unlock(*session.gate);
		return;
	}

	empty_worlds: [..] *World;
	empty_outputs: [..] Retired_Output;
	empty_sources: [..] *Source_Backing;
	session.retired_worlds = empty_worlds;
	session.retired_outputs = empty_outputs;
	session.retired_sources = empty_sources;
	session.cleanup_pins += 1;
	unlock(*session.gate);
	#if TEST_HOOKS {
		worker_pause(session, .CLEANUP);
	}

	for worlds {
		for * it.syntax {
			release_member_syntax(it);
		}

		for member: it.members {
			if member.source {
				release_source(member.source);
			}

			free(member.filename);
		}

		array_free(it.syntax);
		array_free(it.members);
		free(it);
	}

	for outputs {
		for * it.syntax {
			release_member_syntax(it);
		}

		array_free(it.syntax);
		if it.diagnostics {
			release_diagnostics_projection(it.diagnostics);
		}
	}

	for sources {
		release_source(it);
	}

	array_free(worlds);
	array_free(outputs);
	array_free(sources);
	lock(*session.gate);
	session.cleanup_pins -= 1;
	check_stopped(session);
	wake_all(*session.changed);
	unlock(*session.gate);
}

stage_provider_copy :: (model: *Provider_Model) -> *Provider_Model {
	staged := New(Provider_Model);
	staged.* = model.*;
	documents: [..] *Document_State;
	for model.documents {
		copy := New(Document_State);
		copy.* = it.*;
		revisions: [..] [] u8;
		array_add(*revisions, ..it.used_revisions);
		copy.used_revisions = revisions;
		if copy.disk.source {
			retain_source(copy.disk.source);
		}

		if copy.has_overlay {
			retain_source(copy.overlay.source);
		}

		array_add(*documents, copy);
	}

	staged.documents = documents;
	contexts: [..] Admitted_Context;
	array_add(*contexts, ..model.contexts);
	staged.contexts = contexts;
	storage: [..] *Pool;
	staged.batch_storage = storage;
	return staged;
}

commit_provider_copy :: (model: *Provider_Model, staged: *Provider_Model) {
	model.documents, staged.documents = staged.documents, model.documents;
	model.contexts, staged.contexts = staged.contexts, model.contexts;
	model.frontier_counter = staged.frontier_counter;
	model.accepted_frontier = staged.accepted_frontier;
	array_add(*model.batch_storage, ..staged.batch_storage);
	array_free(staged.batch_storage);
	storage: [..] *Pool;
	staged.batch_storage = storage;
}

release_provider_copy :: (staged: *Provider_Model) {
	for staged.documents {
		if it.disk.source {
			release_source(it.disk.source);
		}

		if it.has_overlay {
			release_source(it.overlay.source);
		}

		array_free(it.used_revisions);
		free(it);
	}

	for staged.batch_storage {
		release(it);
		free(it);
	}

	array_free(staged.documents);
	array_free(staged.contexts);
	array_free(staged.batch_storage);
	free(staged);
}
