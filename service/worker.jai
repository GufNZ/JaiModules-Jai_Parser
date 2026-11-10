#scope_module

use_call :: (service: *Service, handle: Handle($K)) -> *Session #expand {
	session := enter_call(service, handle);
	`defer leave_call(session);

	return session;
}

use_owner :: (service: *Service, owner_service: *void, owner_token: u64) -> *Session #expand {
	session := enter_owner(service, owner_service, owner_token);
	`defer leave_call(session);

	return session;
}

lock :: (mutex: *Mutex, body: Code, enabled := true) #expand {
	if enabled {
		lock(mutex);
	}

	defer {
		if enabled {
			unlock(mutex);
		}
	}

	#insert body;
}

unlock :: (mutex: *Mutex, body: Code) #expand {
	unlock(mutex);
	defer lock(mutex);

	#insert body;
}

#scope_export

#if TEST_HOOKS {
	with_lock :: (mutex: *Mutex, body: Code, enabled := true) #expand {
		lock(mutex, body, enabled);
	}
}

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


	session: *Session;
	lock(
		*service.directory,
		#code {
			for service.sessions {
				if it.registry.owner_token == owner_token {
					session = it;
					break;
				}
			}


			if session {
				session.call_pins += 1;
			}
		}
	);

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
	reclaim: bool;
	retired_sessions: [..] *Session;
	empty_sessions: [..] *Session;
	lock(
		*service.directory,
		#code {
			session.call_pins -= 1;
			session.directory_retiring ||= retiring;
			reclaim = session.directory_retiring && !session.call_pins;
			if reclaim {
				for service.sessions {
					if it == session {
						remove it;
					}
				}

				if !service.sessions.count {
					retired_sessions = service.sessions;
					service.sessions = empty_sessions;
				}
			}
		}
	);

	array_free(retired_sessions);
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

admit_directory :: (session: *Session) -> bool {
	service := session.service;
	allocator := service.allocator;
	#if TEST_HOOKS {
		if service.directory_allocator.proc {
			allocator = service.directory_allocator;
		}

		if service.session_owned_directory {
			allocator = owner_allocator(session);
		}
	}

	candidate: [..] *Session;
	empty: [..] *Session;
	observed_count: s64;
	defer array_free(candidate);

	while true {
		admitted: bool;
		capacity: s64;
		retired: [..] *Session;
		lock(
			*service.directory,
			#code {
				#if TEST_HOOKS {
					if service.reject_changed_directory && candidate.allocated && service.sessions.count != observed_count {
						return false;
					}
				}


				if service.sessions.count == service.sessions.allocated && candidate.allocated > service.sessions.count {
					candidate.count = service.sessions.count;
					memcpy(candidate.data, service.sessions.data, candidate.count * size_of(*Session));
					retired = service.sessions;
					service.sessions = candidate;
					candidate = empty;
				}

				if service.sessions.count < service.sessions.allocated {
					service.sessions.data[service.sessions.count] = session;
					service.sessions.count += 1;
					admitted = true;
				} else if service.sessions.allocated <= S64_MAX / size_of(*Session) / 2 {
					capacity = max(8, service.sessions.allocated * 2);
					observed_count = service.sessions.count;
				}
			}
		);

		array_free(retired);
		if admitted {
			return true;
		}


		if !capacity {
			return false;
		}


		array_free(candidate);
		candidate = empty;
		ok, storage := try_output_array(allocator, capacity, *Session);
		if !ok {
			#if TEST_HOOKS {
				if service.retry_failed_directory_allocation {
					continue;
				}
			}


			return false;
		}


		candidate.data = storage.data;
		candidate.allocated = storage.count;
		candidate.allocator = allocator;
	}


	return false;
}

start_workers :: (session: *Session) -> bool {
	#if TEST_HOOKS {
		if session.service.fail_worker_startup {
			return false;
		}
	}


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

	lock(
		*session.gate,
		#code {
			while session.lifecycle == .OPEN {
				mailbox := select_task(session);
				if !mailbox {
					wait(*session.changed, *session.gate);
					continue;
				}


				unlock(
					*session.gate,
					#code {
						#if TEST_HOOKS {
							worker_pause(session, .SELECTED);
						}

						compute_task(session, mailbox);
						#if TEST_HOOKS {
							worker_pause(session, .PUBLICATION);
						}
					}
				);

				deliver_mailbox(session, mailbox);
				wake_all(*session.changed);
				unlock(
					*session.gate,
					#code {
						cleanup_owned(session);
						reset_temporary_storage();
					}
				);
			}
		}
	);

	return 0;
}

stop_requested :: (session: *Session, task: *Task) -> bool {
	stopped: bool;
	lock(
		*session.gate,
		#code {
			stopped = task.phase == .STOP_REQUESTED;
		},
		enabled = session.threaded
	);

	return stopped;
}

reaper_job :: (thread: *Thread) -> s64 {
	session := thread.data.(*Session);
	push_allocator(owner_allocator(session));

	lock(
		*session.gate,
		#code {
			while session.lifecycle == .OPEN {
				wait(*session.changed, *session.gate);
			}
		}
	);

	thread_is_done(*session.compute, -1);
	thread_deinit(*session.compute);
	lock(
		*session.gate,
		#code {
			session.worker_joined = true;
			while session.active_admissions {
				wait(*session.changed, *session.gate);
			}
		}
	);

	cleanup_owned(session);
	lock(
		*session.gate,
		#code {
			while session.cleanup_pins {
				wait(*session.changed, *session.gate);
			}

			check_stopped(session);
			wake_all(*session.changed);
		}
	);

	return 0;
}

cleanup_owned :: (session: *Session) {
	push_allocator(owner_allocator(session));
	worlds: [..] *World;
	outputs: [..] Retired_Output;
	sources: [..] *Source_Backing;
	lock(
		*session.gate,
		#code {
			worlds = session.retired_worlds;
			outputs = session.retired_outputs;
			sources = session.retired_sources;
			if !worlds.count && !outputs.count && !sources.count {
				check_stopped(session);
				return;
			}


			empty_worlds: [..] *World;
			empty_outputs: [..] Retired_Output;
			empty_sources: [..] *Source_Backing;
			session.retired_worlds = empty_worlds;
			session.retired_outputs = empty_outputs;
			session.retired_sources = empty_sources;
			session.cleanup_pins += 1;
		}
	);

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
	lock(
		*session.gate,
		#code {
			session.cleanup_pins -= 1;
			check_stopped(session);
			wake_all(*session.changed);
		}
	);
}

finish_analysis_receipt :: (
	session: *Session,
	frontier: *[] u8,
	documents: *[] [] u8,
	output: *[] u8,
	allocator: Allocator
) {
	unlock(
		*session.gate,
		#code {
			free(output.data,, allocator);
			output.* = .[];
			for documents.* {
				free(it.data);
			}

			free(documents.data);
			documents.* = .[];
			free(frontier.data);
			frontier.* = .[];
		}
	);
}

finish_source_admission :: (
	session: *Session,
	staged: *Provider_Model,
	transfer: *[..] *Pool,
	output: *[] u8,
	error: *Operation_Error,
	allocator: Allocator
) {
	unlock(
		*session.gate,
		#code {
			free(output.data,, allocator);
			output.* = .[];
			free(error.path.data,, allocator);
			free(error.document.data,, allocator);
			error.* = .{};
			#if TEST_HOOKS {
				retained_source := session.faults.retain_source_batch_reference;
				if retained_source {
					session.faults.retain_source_batch_reference = null;
					retain_source(retained_source);
				}
			}

			release_provider_copy(staged);
			array_free(transfer.*);
		}
	);

	session.active_admissions -= 1;
	give(session, .CONCURRENT_ACQUISITIONS);
	wake_all(*session.changed);
}

stage_provider_copy :: (model: *Provider_Model, backing: *Source_Provider_Backing) {
	staged := backing.model;
	staged.* = model.*;
	documents: [..] *Document_State;
	documents.data = backing.documents.data;
	documents.allocated = backing.documents.count;
	for model.documents {
		copy := backing.documents[it_index];
		revisions := copy.used_revisions;
		copy.* = it.*;
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
	contexts.data = backing.contexts.data;
	contexts.allocated = backing.contexts.count;
	array_add(*contexts, ..model.contexts);
	staged.contexts = contexts;
	storage: [..] *Pool;
	staged.batch_storage = storage;
}

commit_provider_copy :: (model: *Provider_Model, staged: *Provider_Model, transfer: *[..] *Pool) {
	if model.batch_storage.count + staged.batch_storage.count > model.batch_storage.allocated {
		assert(transfer.allocated >= model.batch_storage.count + staged.batch_storage.count);
		memcpy(transfer.data, model.batch_storage.data, model.batch_storage.count * size_of(*Pool));
		transfer.count = model.batch_storage.count;
		model.batch_storage, transfer.* = transfer.*, model.batch_storage;
	}

	model.documents, staged.documents = staged.documents, model.documents;
	model.contexts, staged.contexts = staged.contexts, model.contexts;
	model.frontier_counter = staged.frontier_counter;
	model.accepted_frontier = staged.accepted_frontier;
	array_add(*model.batch_storage, ..staged.batch_storage);
	staged.batch_storage.count = 0;
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
