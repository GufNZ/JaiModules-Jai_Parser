// Phase-4 harness host tests: project root and epoch binding, disk and overlay events, host confirmations and serial completion dispatch.
// Uses the default service import and native workers, with no test hooks.
// Run from this directory: jai service_host_test.jai -x64 -quiet && ./service_host_test.exe
#import "Basic";
#import "File";
#import "File_Utilities";

Service :: #import "Jai_Parser/service";

main :: () {
	root := tprint("%.build/host_test", #filepath);
	if file_exists(root) {
		delete_directory(root);
	}

	make_directory_if_it_does_not_exist(root, recursive = true);

	test_open(root);
	test_disk_and_overlay(root);
	test_absence_and_unavailability(root);
	test_dispatch(root);
	print("Service host \e[92mPASS\e[0m.\n");
}

limits :: () -> Service.Limits, Service.Limits {
	ceilings: Service.Limits;
	for * ceilings.values {
		it.* = 1 << 20;
	}

	minima: Service.Limits;
	minima.values[Service.Limit_Name.LIVE_HANDLES] = 2;
	minima.values[Service.Limit_Name.IN_FLIGHT_OPERATIONS] = 1;
	return ceilings, minima;
}

open :: (root: string) -> *Service.Harness_Host {
	ceilings, minima := limits();
	failure, host, error := Service.open_harness_host(root, ceilings, minima);
	assert(failure == .NONE, "\e[91mHost failed to open: % %.\e[0m", failure, error);
	return host;
}

FOREVER :: 0xFFFF_FFFF_FFFF_FFFF;

// Waits for the ticket's milestone through the public condition-variable wait.
await :: (host: *Service.Harness_Host, ticket: Service.Handle(.TICKET)) -> Service.Observation {
	ok, waited := Service.wait(host.service, ticket, .{clock_identity = host.service.clock_identity, nanoseconds = FOREVER});
	assert(ok && !waited.timed_out);
	return waited.observation;
}

submit :: (batch: *Service.Host_Batch) -> Service.Handle(.TICKET) {
	ok, accepted, error := Service.submit_batch(batch);
	assert(ok, "\e[91mSubmit failed: %.\e[0m", error);
	return accepted.ticket;
}

world_of :: (host: *Service.Harness_Host, ticket: Service.Handle(.TICKET)) -> Service.Handle(.WORLD) {
	observation := await(host, ticket);
	assert(observation.update.kind == .PUBLISHED, "\e[91mUpdate ended %.\e[0m", observation.update.kind);
	ok, acquisition := Service.acquire_world(host.service, .{kind = .PUBLISHED_UPDATE, ticket = ticket});
	assert(ok && acquisition.kind == .ACQUIRED);
	return acquisition.world;
}

snapshot_text :: (host: *Service.Harness_Host, world: Service.Handle(.WORLD), relative: string) -> string {
	ok, start := Service.query(host.service, .{version = Service.INTERFACE_VERSION, world = world, document = Service.harness_document(host, relative), kind = .SYNTAX_SNAPSHOT});
	assert(ok && start.kind == .AVAILABLE);
	_, description := Service.read_result(host.service, start.result);
	text := copy_string(description.snapshot.source,, temp);
	Service.release(host.service, start.result);
	return text;
}

tracked :: (host: *Service.Harness_Host, relative: string) -> Service.Tracked_Document {
	_, description := Service.describe_session(host.service, host.session);
	for description.tracked_document_states {
		if Service.bytes_equal(it.document, Service.harness_document(host, relative)) {
			return it;
		}
	}


	assert(false, "\e[91m% is not tracked.\e[0m", relative);
	return .{};
}

test_open :: (root: string) {
	ceilings, minima := limits();
	failure := Service.open_harness_host(tprint("%/missing", root), ceilings, minima);
	assert(failure == .INVALID_ROOT);

	// Each host reserves a fresh epoch in the root, so its incarnation and session identities never repeat.
	first := open(root);
	second := open(root);
	assert(second.epoch == first.epoch + 1 && !Service.bytes_equal(first.session_identity.([] u8), second.session_identity.([] u8)));
	assert(file_exists(tprint("%/%", root, Service.EPOCH_FILE_NAME)));

	for string.["", "/a.jai", "../a.jai", "a/../b.jai", "a//b.jai", "./a.jai", "a\\b.jai", "C:a.jai"] {
		assert(!Service.valid_relative(it), "\e[91mRelative path '%' was accepted.\e[0m", it);
	}

	batch := Service.begin_batch(first);
	assert(!Service.set_overlay(*batch, "../escape.jai", "x"), "\e[91mA path outside the root was accepted.\e[0m");
	assert(!batch.events.count);

	for (*Service.Harness_Host).[first, second] {
		closed := Service.close_harness_host(it);
		assert(closed);
	}

	print("Open \e[92mPASS\e[0m\n");
}

// V1/T3/T4 through the host: overlays stay selected over disk changes, saves clear only matching bytes, and reset/restore need confirmations.
test_disk_and_overlay :: (root: string) {
	host := open(root);
	path := tprint("%/a.jai", root);
	write_entire_file(path, "a :: 1;");

	batch := Service.begin_batch(host);
	assert(Service.observe_disk(*batch, "a.jai"));
	ticket_a := submit(*batch);
	world_a := world_of(host, ticket_a);
	assert(snapshot_text(host, world_a, "a.jai") == "a :: 1;");

	batch = Service.begin_batch(host);
	assert(Service.set_overlay(*batch, "a.jai", "b :: 2;"));
	ticket_b := submit(*batch);
	world_b := world_of(host, ticket_b);
	assert(snapshot_text(host, world_b, "a.jai") == "b :: 2;");

	// An external disk change advances the disk branch only; the overlay stays selected and A's world is unchanged.
	write_entire_file(path, "c :: 3;");
	batch = Service.begin_batch(host);
	assert(Service.observe_disk(*batch, "a.jai"));
	ticket_c := submit(*batch);
	world_c := world_of(host, ticket_c);
	state := tracked(host, "a.jai");
	assert(state.selection == .OVERLAY && Service.bytes_equal(state.disk_source_revision, Service.source_revision_of(xx "c :: 3;")));
	assert(snapshot_text(host, world_c, "a.jai") == "b :: 2;" && snapshot_text(host, world_a, "a.jai") == "a :: 1;");

	// The host writes the overlay's bytes and acknowledges the save; the overlay is cleared and disk selected.
	write_entire_file(path, "b :: 2;");
	batch = Service.begin_batch(host);
	assert(Service.ack_save(*batch, "a.jai"));
	ticket_save := submit(*batch);
	await(host, ticket_save);
	assert(tracked(host, "a.jai").selection == .DISK && !tracked(host, "a.jai").has_overlay);

	// A save of different bytes keeps the overlay.
	batch = Service.begin_batch(host);
	assert(Service.set_overlay(*batch, "a.jai", "d :: 4;"));
	ticket_d := submit(*batch);
	batch = Service.begin_batch(host);
	assert(Service.ack_save(*batch, "a.jai"));
	ok, _, error := Service.submit_batch(*batch);
	assert(!ok && error.code == .INVALID_ARGUMENT, "\e[91mA save of different bytes was accepted.\e[0m");
	assert(tracked(host, "a.jai").selection == .OVERLAY);

	// T4: reset selects the current disk bytes; restoring the discarded overlay is a separate confirmed event.
	batch = Service.begin_batch(host);
	assert(Service.reset_overlay(*batch, "a.jai"));
	ticket_reset := submit(*batch);
	world_reset := world_of(host, ticket_reset);
	assert(snapshot_text(host, world_reset, "a.jai") == "b :: 2;" && tracked(host, "a.jai").selection == .DISK);

	batch = Service.begin_batch(host);
	assert(Service.restore_overlay(*batch, "a.jai", "d :: 4;", xx "candidate-1"));
	ticket_restore := submit(*batch);
	world_restore := world_of(host, ticket_restore);
	assert(snapshot_text(host, world_restore, "a.jai") == "d :: 4;" && tracked(host, "a.jai").selection == .RESTORED_OVERLAY);

	for Service.Handle(.WORLD).[world_a, world_b, world_c, world_reset, world_restore] {
		Service.release(host.service, it);
	}

	for Service.Handle(.TICKET).[ticket_a, ticket_b, ticket_c, ticket_save, ticket_d, ticket_reset, ticket_restore] {
		Service.release(host.service, it);
	}

	closed := Service.close_harness_host(host);
	assert(closed);
	print("Disk and overlay \e[92mPASS\e[0m\n");
}

// A deleted file is confirmed absence with no syntax; an unreadable path is not absence and produces no event.
test_absence_and_unavailability :: (root: string) {
	host := open(root);
	path := tprint("%/gone.jai", root);
	write_entire_file(path, "x :: 1;");
	batch := Service.begin_batch(host);
	assert(Service.observe_disk(*batch, "gone.jai"));
	ticket := submit(*batch);
	await(host, ticket);

	file_delete(path);
	batch = Service.begin_batch(host);
	assert(Service.observe_disk(*batch, "gone.jai"));
	ticket_absent := submit(*batch);
	world := world_of(host, ticket_absent);
	ok, start := Service.query(host.service, .{version = Service.INTERFACE_VERSION, world = world, document = Service.harness_document(host, "gone.jai"), kind = .SYNTAX_SNAPSHOT});
	assert(ok && start.kind == .TERMINAL && start.observation.query.unavailable == .SOURCE_ABSENT);

	make_directory_if_it_does_not_exist(tprint("%/folder.jai", root));
	batch = Service.begin_batch(host);
	assert(!Service.observe_disk(*batch, "folder.jai"), "\e[91mAn unreadable path was reported.\e[0m");

	Service.release(host.service, world);
	Service.release(host.service, ticket);
	Service.release(host.service, ticket_absent);
	closed := Service.close_harness_host(host);
	assert(closed);
	print("Absence and unavailability \e[92mPASS\e[0m\n");
}

Dispatch_Log :: struct {
	host: *Service.Harness_Host;
	delivered: s64;
	nested_returned: s64;
}

dispatch_log: Dispatch_Log;

// Re-enters dispatch from inside a handler and fails every second record.
log_completion :: (host: *Service.Harness_Host, record: Service.Completion_Record) -> bool {
	dispatch_log.delivered += 1;
	dispatch_log.nested_returned += Service.dispatch_completions(host, log_completion);
	return dispatch_log.delivered % 2 == 1;
}

test_dispatch :: (root: string) {
	host := open(root);
	waiters: [3] Service.Handle(.WAITER);
	tickets: [3] Service.Handle(.TICKET);
	for 0..2 {
		write_entire_file(tprint("%/d%.jai", root, it), tprint("d% :: %;", it, it));
		batch := Service.begin_batch(host);
		assert(Service.observe_disk(*batch, tprint("d%.jai", it)));
		tickets[it] = submit(*batch);
		_, observed := Service.observe_ticket(host.service, tickets[it]);
		waiters[it] = observed.waiter;
	}

	// The last ticket publishes; the two earlier ones were superseded at once when the next batch was accepted.
	await(host, tickets[2]);
	delivered := Service.dispatch_completions(host, log_completion, batch_size = 1);
	assert(delivered == 3 && dispatch_log.delivered == 3 && !dispatch_log.nested_returned, "\e[91mDispatch was not serial.\e[0m");
	assert(host.dispatch_failures == 1);
	assert(!Service.dispatch_completions(host, log_completion), "\e[91mA delivered record was dispatched again.\e[0m");

	for waiters {
		Service.release(host.service, it);
	}

	for tickets {
		Service.release(host.service, it);
	}

	closed := Service.close_harness_host(host);
	assert(closed);
	print("Dispatch \e[92mPASS\e[0m\n");
}
