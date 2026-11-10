// Phase-4 source provider model tests: descriptor admission, overlay and disk events, atomic batch rejection and retained backings.
// Run from this directory: jai service_provider_test.jai -x64 -quiet && ./service_provider_test.exe
#import "Basic";

Service :: #import "Jai_Parser/service";

NAMESPACE :: "test-provider";
HOST :: "test-host";
POLICY :: 1;

main :: () {
	test_descriptor();
	test_overlay_chain();
	test_atomic_batch();
	test_save_race();
	test_reset_restore();
	test_contexts_and_bindings();
	test_capabilities_and_limits();
	print("Service provider \e[92mPASS\e[0m.\n");
}

descriptor :: () -> Service.Provider_Adapter_Descriptor {
	return .{
		adapter_schema = Service.SOURCE_PROVIDER_SCHEMA,
		authority_identity = xx NAMESPACE,
		document_policy_version = POLICY,
		path_platform = .WINDOWS_UTF16LE,
		consistency_capabilities = .IMMUTABLE_CAPTURE,
	};
}

open :: (batch_events := 8, source_bytes := 1024) -> *Service.Provider_Model {
	incarnation := Service.make_service_incarnation(xx "test-authority", 1);
	_, identities := Service.issue_session(*incarnation);
	limits: Service.Limits;
	for * limits.values {
		it.* = 1 << 20;
	}

	limits.values[Service.Limit_Name.BATCH_EVENTS] = batch_events;
	limits.values[Service.Limit_Name.SOURCE_BYTES] = source_bytes;
	return Service.open_provider_model(descriptor(), xx NAMESPACE, identities.session, xx HOST, limits);
}

doc :: (key: string) -> [] u8 {
	return Service.document_id(xx NAMESPACE, POLICY, xx key);
}

rev :: (model: *Service.Provider_Model, document: [] u8, token: string) -> [] u8 {
	return Service.provider_revision_id(model.provider_namespace, model.session, document, xx token);
}

registration :: (filename: string) -> Service.Context_Registration {
	paths: Service.Context_Paths;
	_, paths.visible_filename = Service.windows_path_value(filename);
	_, paths.visible_directory = Service.windows_path_value("D:/project");
	_, paths.relative_base = Service.windows_path_value("D:/project");
	ok, descriptor := Service.syntax_context_descriptor(paths);
	assert(ok);
	return .{identity = Service.context_id(descriptor), descriptor = descriptor};
}

binding :: (document: [] u8, path := "D:/project/main.jai") -> *Service.Document_Binding {
	result := New(Service.Document_Binding);
	result.document = document;
	result.provider_policy_version = POLICY;
	_, result.absolute_path = Service.windows_path_value(path);
	return result;
}

revision_state :: (revision: [] u8) -> Service.Expected_Provider_State {
	return .{kind = .REVISION, revision = revision};
}

inline_source :: (text: string) -> Service.Source_Input {
	return .{kind = .INLINE_BYTES, bytes = xx text};
}

provenance :: () -> Service.Observation_Provenance {
	return .{provider_identity = xx NAMESPACE, observation_token = xx "observation"};
}

present :: (text: string, syntax_context: [] u8) -> Service.Disk_Observation {
	return .{
		kind = .PRESENT,
		source = inline_source(text),
		source_revision = Service.source_revision_of(xx text),
		syntax_context = syntax_context,
		provenance = provenance(),
	};
}

set_overlay :: (document: [] u8, expected: Service.Expected_Provider_State, syntax_context: [] u8, text: string, resulting: [] u8) -> Service.Document_Event {
	return .{
		document = document,
		expected_provider_state = expected,
		source_context = syntax_context,
		binding = ifx expected.kind == .UNTRACKED then binding(document),
		kind = .SET_OVERLAY,
		source = inline_source(text),
		resulting_provider_revision = resulting,
	};
}

submit :: (model: *Service.Provider_Model, contexts: [] Service.Context_Registration, events: .. Service.Document_Event) -> bool, Service.Operation_Error {
	batch := Service.Source_Batch.{
		version = Service.INTERFACE_VERSION,
		session = model.session,
		expected_frontier = model.accepted_frontier,
		contexts = contexts,
		events = events,
	};
	ok, _, error := Service.apply_source_batch(model, batch);
	return ok, error;
}

// A rejected batch leaves the frontier and the named document's revision exactly as they were.
expect_rejected :: (model: *Service.Provider_Model, ok: bool, error: Service.Operation_Error, code: Service.Operation_Error_Code, frontier: [] u8, what: string) {
	assert(!ok, "\e[91m%: accepted.\e[0m", what);
	assert(error.code == code, "\e[91m%: expected %, got %.\e[0m", what, code, error.code);
	assert(Service.bytes_equal(model.accepted_frontier, frontier), "\e[91m%: the frontier moved.\e[0m", what);
}

selected_text :: (model: *Service.Provider_Model, document: [] u8) -> string, Service.Selected_Document {
	state := Service.find_document(model, document);
	assert(state != null);
	selected := Service.selected_document(state);
	text := ifx selected.source then selected.source.bytes.(string);
	return text, selected;
}

test_descriptor :: () {
	assert(Service.validate_provider_descriptor(descriptor()) == .NONE);
	controls: [5] Service.Provider_Adapter_Descriptor;
	expected := Service.Provider_Failure.[.SCHEMA, .AUTHORITY, .ALIAS_POLICY, .CONSISTENCY, .LEASE];
	for * controls {
		it.* = descriptor();
	}

	controls[0].adapter_schema = "jai-cache-source-provider/2";
	controls[1].authority_identity = .[];
	controls[2].case_alias_link_policy.kind = .HOST_VALIDATED_ALIASES;
	controls[3].consistency_capabilities = 0;
	controls[4].lease_capabilities.kind = .IMMUTABLE_RETAIN_RELEASE;
	for controls {
		failure := Service.validate_provider_descriptor(it);
		assert(failure == expected[it_index], "\e[91mControl %: expected %, got %.\e[0m", it_index, expected[it_index], failure);
	}

	print("Provider descriptor \e[92mPASS\e[0m\n");
}

test_overlay_chain :: () {
	model := open();
	defer Service.close_provider_model(model);

	context_a := registration("D:/project/main.jai");
	main_doc := doc("main");
	initial := model.accepted_frontier;
	ok, error := submit(model, .[context_a], set_overlay(main_doc, .{}, context_a.identity, "abc", rev(model, main_doc, "1")));
	assert(ok, "\e[91mSET_OVERLAY failed: %.\e[0m", error);
	assert(!Service.bytes_equal(model.accepted_frontier, initial));

	// V7: a capture that retained the old backing keeps its exact bytes after the overlay is replaced.
	text, selected := selected_text(model, main_doc);
	assert(text == "abc" && selected.selection == .OVERLAY && Service.bytes_equal(selected.overlay_revision, rev(model, main_doc, "1")));
	retained := selected.source;
	Service.retain_source(retained);

	// Edits apply in order, each to the previous edit's result.
	edit := Service.Document_Event.{
		document = main_doc,
		expected_provider_state = revision_state(rev(model, main_doc, "1")),
		source_context = context_a.identity,
		kind = .EDIT_OVERLAY,
		base_source_revision = Service.source_revision_of(xx "abc"),
		edits = .[
			.{start_byte = 1, end_byte = 2, replacement = xx "XY"},
			.{start_byte = 0, end_byte = 1},
		],
		resulting_provider_revision = rev(model, main_doc, "2"),
	};
	ok, error = submit(model, .[], edit);
	assert(ok, "\e[91mEDIT_OVERLAY failed: %.\e[0m", error);
	text = selected_text(model, main_doc);
	assert(text == "XYc");
	assert(retained.bytes.(string) == "abc" && Service.bytes_equal(retained.revision, Service.source_revision_of(xx "abc")));
	Service.release_source(retained);

	// Stale and invalid edits reject without changing the tracked state.
	frontier := model.accepted_frontier;
	stale := edit;
	stale.expected_provider_state = revision_state(rev(model, main_doc, "2"));
	stale.resulting_provider_revision = rev(model, main_doc, "3");
	ok, error = submit(model, .[], stale);
	expect_rejected(model, ok, error, .BASE_MISMATCH, frontier, "stale source base");
	assert(error.scope == .SOURCE);

	stale = edit;
	stale.base_source_revision = Service.source_revision_of(xx "XYc");
	stale.resulting_provider_revision = rev(model, main_doc, "3");
	ok, error = submit(model, .[], stale);
	expect_rejected(model, ok, error, .BASE_MISMATCH, frontier, "stale provider revision");
	assert(error.scope == .DOCUMENT && Service.bytes_equal(error.document, main_doc));

	stale.expected_provider_state = revision_state(rev(model, main_doc, "2"));
	stale.edits = .[.{start_byte = 2, end_byte = 4}];
	ok, error = submit(model, .[], stale);
	expect_rejected(model, ok, error, .INVALID_ARGUMENT, frontier, "edit past the end");
	assert(error.rule == .OUT_OF_RANGE && error.path.count == 4 && error.path[3].index == 0);

	stale.edits = .[.{start_byte = 0, end_byte = 1}];
	stale.resulting_provider_revision = rev(model, main_doc, "1");
	ok, error = submit(model, .[], stale);
	expect_rejected(model, ok, error, .INVALID_ARGUMENT, frontier, "reused provider revision");
	assert(error.rule == .DUPLICATE);

	stale.resulting_provider_revision = rev(model, main_doc, "3");
	batch := Service.Source_Batch.{
		version = Service.INTERFACE_VERSION,
		session = model.session,
		expected_frontier = initial,
		events = .[stale],
	};
	ok, _, error = Service.apply_source_batch(model, batch);
	expect_rejected(model, ok, error, .BASE_MISMATCH, frontier, "stale frontier");
	assert(error.scope == .FRONTIER);

	batch.expected_frontier = frontier;
	batch.version = "jai-cache-interface/2";
	ok, _, error = Service.apply_source_batch(model, batch);
	expect_rejected(model, ok, error, .INVALID_VERSION, frontier, "version");

	text = selected_text(model, main_doc);
	state := Service.find_document(model, main_doc);
	assert(text == "XYc" && Service.bytes_equal(state.provider_revision, rev(model, main_doc, "2")));
	print("Overlay chain \e[92mPASS\e[0m\n");
}

// V5: one invalid member rejects every member, including an otherwise valid new document.
test_atomic_batch :: () {
	model := open();
	defer Service.close_provider_model(model);

	context_a := registration("D:/project/main.jai");
	first := doc("first");
	second := doc("second");
	ok, error := submit(model, .[context_a], set_overlay(first, .{}, context_a.identity, "one", rev(model, first, "1")));
	assert(ok);

	frontier := model.accepted_frontier;
	valid := set_overlay(second, .{}, context_a.identity, "two", rev(model, second, "1"));
	invalid := set_overlay(first, .{}, context_a.identity, "again", rev(model, first, "2"));
	ok, error = submit(model, .[], valid, invalid);
	expect_rejected(model, ok, error, .BASE_MISMATCH, frontier, "untracked expectation for a tracked document");
	assert(error.scope == .DOCUMENT && Service.bytes_equal(error.document, first));
	assert(!Service.find_document(model, second), "\e[91mThe valid member was committed.\e[0m");

	ok, error = submit(model, .[], valid, valid);
	expect_rejected(model, ok, error, .INVALID_ARGUMENT, frontier, "duplicate document");
	assert(error.rule == .DUPLICATE && error.path[1].index == 1);

	ok, error = submit(model, .[]);
	expect_rejected(model, ok, error, .INVALID_ARGUMENT, frontier, "empty batch");
	assert(error.rule == .MISSING);

	ok, error = submit(model, .[], valid, set_overlay(first, revision_state(rev(model, first, "1")), context_a.identity, "uno", rev(model, first, "2")));
	assert(ok);
	documents := Service.tracked_documents(model);
	assert(documents.count == 2 && Service.compare_canonical(documents[0].document, documents[1].document) < 0);

	// The model owns copies of every accepted byte string; the caller's buffers may be reused.
	third := array_copy(doc("third"));
	third_revision := array_copy(rev(model, third, "1"));
	ok, error = submit(model, .[], set_overlay(third, .{}, context_a.identity, "three", third_revision));
	assert(ok);
	memset(third.data, 0, third.count);
	memset(third_revision.data, 0, third_revision.count);
	state := Service.find_document(model, doc("third"));
	assert(state && Service.bytes_equal(state.provider_revision, rev(model, doc("third"), "1")) && Service.bytes_equal(state.binding.document, doc("third")));
	print("Atomic batches \e[92mPASS\e[0m\n");
}

// T3: a save acknowledgement for an older overlay installation records the disk branch and preserves the newer overlay.
test_save_race :: () {
	model := open();
	defer Service.close_provider_model(model);

	context_a := registration("D:/project/main.jai");
	main_doc := doc("main");
	ok, error := submit(model, .[context_a], set_overlay(main_doc, .{}, context_a.identity, "B", rev(model, main_doc, "1")));
	assert(ok);
	ok, error = submit(model, .[], set_overlay(main_doc, revision_state(rev(model, main_doc, "1")), context_a.identity, "C", rev(model, main_doc, "2")));
	assert(ok);

	save := Service.Document_Event.{
		document = main_doc,
		expected_provider_state = revision_state(rev(model, main_doc, "2")),
		source_context = context_a.identity,
		kind = .ACK_SAVE,
		disk = present("B", context_a.identity),
		written_source_revision = Service.source_revision_of(xx "B"),
		expected_overlay_revision = rev(model, main_doc, "1"),
		resulting_provider_revision = rev(model, main_doc, "3"),
	};
	ok, error = submit(model, .[], save);
	assert(ok, "\e[91mACK_SAVE failed: %.\e[0m", error);
	text, selected := selected_text(model, main_doc);
	state := Service.find_document(model, main_doc);
	assert(text == "C" && selected.selection == .OVERLAY && state.disk.kind == .PRESENT && state.disk.source.bytes.(string) == "B");

	// Acknowledging the current installation clears it only when the written bytes are the overlay's bytes.
	frontier := model.accepted_frontier;
	save.expected_provider_state = revision_state(rev(model, main_doc, "3"));
	save.expected_overlay_revision = rev(model, main_doc, "2");
	save.resulting_provider_revision = rev(model, main_doc, "4");
	ok, error = submit(model, .[], save);
	expect_rejected(model, ok, error, .INVALID_ARGUMENT, frontier, "save of different bytes");

	save.disk = present("C", context_a.identity);
	save.written_source_revision = Service.source_revision_of(xx "C");
	ok, error = submit(model, .[], save);
	assert(ok, "\e[91mACK_SAVE failed: %.\e[0m", error);
	text, selected = selected_text(model, main_doc);
	assert(text == "C" && selected.selection == .DISK && selected.provenance != null);

	save.expected_provider_state = revision_state(rev(model, main_doc, "4"));
	save.resulting_provider_revision = rev(model, main_doc, "5");
	save.disk.kind = .ABSENT;
	frontier = model.accepted_frontier;
	ok, error = submit(model, .[], save);
	expect_rejected(model, ok, error, .INVALID_ARGUMENT, frontier, "absent save");
	assert(error.rule == .WRONG_KIND);
	print("Save race \e[92mPASS\e[0m\n");
}

// T4: reset to disk and restore a recovery candidate need a matching host confirmation.
test_reset_restore :: () {
	model := open();
	defer Service.close_provider_model(model);

	context_a := registration("D:/project/main.jai");
	main_doc := doc("main");
	ok, error := submit(model, .[context_a], set_overlay(main_doc, .{}, context_a.identity, "unsaved", rev(model, main_doc, "1")));
	assert(ok);

	reset := Service.Document_Event.{
		document = main_doc,
		expected_provider_state = revision_state(rev(model, main_doc, "1")),
		source_context = context_a.identity,
		kind = .RESET_OVERLAY,
		disk = present("disk", context_a.identity),
		host_confirmation = .{
			host_authority = xx "someone-else",
			confirmation_token = xx "confirm",
			document = main_doc,
			expected_provider_state = revision_state(rev(model, main_doc, "1")),
			action = .RESET,
		},
		resulting_provider_revision = rev(model, main_doc, "2"),
	};
	frontier := model.accepted_frontier;
	ok, error = submit(model, .[], reset);
	expect_rejected(model, ok, error, .INVALID_ARGUMENT, frontier, "foreign confirmation");
	assert(error.rule == .INVALID_CONFIRMATION);

	reset.host_confirmation.host_authority = xx HOST;
	reset.host_confirmation.action = .RESTORE;
	ok, error = submit(model, .[], reset);
	expect_rejected(model, ok, error, .INVALID_ARGUMENT, frontier, "confirmation for another action");

	reset.host_confirmation.action = .RESET;
	ok, error = submit(model, .[], reset);
	assert(ok, "\e[91mRESET_OVERLAY failed: %.\e[0m", error);
	text, selected := selected_text(model, main_doc);
	assert(text == "disk" && selected.selection == .DISK);

	restore := Service.Document_Event.{
		document = main_doc,
		expected_provider_state = revision_state(rev(model, main_doc, "2")),
		source_context = context_a.identity,
		kind = .RESTORE_OVERLAY,
		source = inline_source("unsaved"),
		host_confirmation = .{
			host_authority = xx HOST,
			confirmation_token = xx "confirm-restore",
			document = main_doc,
			expected_provider_state = revision_state(rev(model, main_doc, "2")),
			action = .RESTORE,
			source_revision = Service.source_revision_of(xx "unsaved"),
			recovery_candidate = xx "candidate",
		},
		recovery_candidate = xx "other-candidate",
		resulting_provider_revision = rev(model, main_doc, "3"),
	};
	frontier = model.accepted_frontier;
	ok, error = submit(model, .[], restore);
	expect_rejected(model, ok, error, .INVALID_ARGUMENT, frontier, "confirmation for another candidate");

	restore.recovery_candidate = xx "candidate";
	ok, error = submit(model, .[], restore);
	assert(ok, "\e[91mRESTORE_OVERLAY failed: %.\e[0m", error);
	text, selected = selected_text(model, main_doc);
	assert(text == "unsaved" && selected.selection == .RESTORED_OVERLAY);
	print("Reset and restore \e[92mPASS\e[0m\n");
}

test_contexts_and_bindings :: () {
	model := open();
	defer Service.close_provider_model(model);

	context_a := registration("D:/project/main.jai");
	context_b := registration("D:/project/other.jai");
	main_doc := doc("main");
	frontier := model.accepted_frontier;
	event := set_overlay(main_doc, .{}, context_a.identity, "x", rev(model, main_doc, "1"));

	ok, error := submit(model, .[], event);
	expect_rejected(model, ok, error, .INVALID_ARGUMENT, frontier, "unregistered context");
	assert(error.rule == .INCONSISTENT_BINDING);

	ok, error = submit(model, .[context_a, context_b], event);
	expect_rejected(model, ok, error, .INVALID_ARGUMENT, frontier, "unreferenced registration");
	assert(error.path[0].name == "contexts" && error.path[1].index == 1);

	ok, error = submit(model, .[context_a, context_a], event);
	expect_rejected(model, ok, error, .INVALID_ARGUMENT, frontier, "duplicate registration");
	assert(error.rule == .DUPLICATE);

	forged := context_a;
	forged.identity = context_b.identity;
	ok, error = submit(model, .[forged], event);
	expect_rejected(model, ok, error, .INVALID_ARGUMENT, frontier, "identity of another descriptor");
	assert(error.rule == .INVALID_ENCODING);

	unbound := event;
	unbound.binding = null;
	ok, error = submit(model, .[context_a], unbound);
	expect_rejected(model, ok, error, .INVALID_ARGUMENT, frontier, "missing binding");
	assert(error.rule == .MISSING);

	wrong_policy := event;
	wrong_policy.binding = binding(main_doc);
	wrong_policy.binding.provider_policy_version = POLICY + 1;
	ok, error = submit(model, .[context_a], wrong_policy);
	expect_rejected(model, ok, error, .INVALID_ARGUMENT, frontier, "binding policy");

	posix := event;
	posix.binding = binding(main_doc);
	_, posix.binding.absolute_path = Service.posix_path_value("/project/main.jai");
	ok, error = submit(model, .[context_a], posix);
	expect_rejected(model, ok, error, .INVALID_ARGUMENT, frontier, "path platform");

	foreign := set_overlay(Service.document_id(xx "other-provider", POLICY, xx "main"), .{}, context_a.identity, "x", rev(model, main_doc, "1"));
	ok, error = submit(model, .[context_a], foreign);
	expect_rejected(model, ok, error, .INVALID_ARGUMENT, frontier, "document key of another provider");

	misissued := event;
	misissued.resulting_provider_revision = rev(model, doc("other"), "1");
	ok, error = submit(model, .[context_a], misissued);
	expect_rejected(model, ok, error, .INVALID_ARGUMENT, frontier, "revision for another document");

	edit := event;
	edit.kind = .EDIT_OVERLAY;
	ok, error = submit(model, .[context_a], edit);
	expect_rejected(model, ok, error, .BASE_MISMATCH, frontier, "edit of an untracked document");

	ok, error = submit(model, .[context_a], event);
	assert(ok);

	// A tracked document may repeat its binding exactly, but not change it.
	moved := set_overlay(main_doc, revision_state(rev(model, main_doc, "1")), context_a.identity, "y", rev(model, main_doc, "2"));
	moved.binding = binding(main_doc, "D:/project/moved.jai");
	frontier = model.accepted_frontier;
	ok, error = submit(model, .[], moved);
	expect_rejected(model, ok, error, .INVALID_ARGUMENT, frontier, "changed binding");
	assert(error.rule == .INCONSISTENT_BINDING && error.path[2].name == "binding");

	moved.binding = binding(main_doc);
	ok, error = submit(model, .[], moved);
	assert(ok);

	// The source context names the resulting selection: a disk observation under an overlay keeps the overlay's context.
	observe := Service.Document_Event.{
		document = main_doc,
		expected_provider_state = revision_state(rev(model, main_doc, "2")),
		source_context = context_b.identity,
		kind = .OBSERVE_DISK,
		disk = present("disk", context_b.identity),
		resulting_provider_revision = rev(model, main_doc, "3"),
	};
	frontier = model.accepted_frontier;
	ok, error = submit(model, .[context_b], observe);
	expect_rejected(model, ok, error, .INVALID_ARGUMENT, frontier, "context of the unselected branch");
	assert(error.path[2].name == "source_context");

	observe.source_context = context_a.identity;
	ok, error = submit(model, .[context_b], observe);
	assert(ok, "\e[91mOBSERVE_DISK failed: %.\e[0m", error);
	state := Service.find_document(model, main_doc);
	assert(Service.bytes_equal(state.disk.syntax_context, context_b.identity) && Service.bytes_equal(state.overlay.syntax_context, context_a.identity));
	print("Contexts and bindings \e[92mPASS\e[0m\n");
}

test_capabilities_and_limits :: () {
	model := open(batch_events = 2, source_bytes = 8);
	defer Service.close_provider_model(model);

	context_a := registration("D:/project/main.jai");
	main_doc := doc("main");
	frontier := model.accepted_frontier;
	event := set_overlay(main_doc, .{}, context_a.identity, "x", rev(model, main_doc, "1"));

	rename := event;
	rename.kind = .RENAME;
	ok, error := submit(model, .[context_a], rename);
	expect_rejected(model, ok, error, .UNSUPPORTED_EVENT, frontier, "rename");
	assert(error.event_tag == "RENAME");

	lease := event;
	lease.source.kind = .PROVIDER_LEASE;
	ok, error = submit(model, .[context_a], lease);
	expect_rejected(model, ok, error, .ADMISSION_DENIED, frontier, "provider lease");
	assert(error.admission.kind == .CAPABILITY);

	large := set_overlay(main_doc, .{}, context_a.identity, "too large", rev(model, main_doc, "1"));
	ok, error = submit(model, .[context_a], large);
	expect_rejected(model, ok, error, .ADMISSION_DENIED, frontier, "source bytes");
	assert(error.admission.kind == .LIMIT && error.admission.limit == .SOURCE_BYTES);

	ok, error = submit(
		model,
		.[context_a],
		event,
		set_overlay(doc("b"), .{}, context_a.identity, "b", rev(model, doc("b"), "1")),
		set_overlay(doc("c"), .{}, context_a.identity, "c", rev(model, doc("c"), "1"))
	);
	expect_rejected(model, ok, error, .ADMISSION_DENIED, frontier, "batch events");
	assert(error.admission.limit == .BATCH_EVENTS);

	observe := Service.Document_Event.{
		document = main_doc,
		source_context = context_a.identity,
		binding = binding(main_doc),
		kind = .OBSERVE_DISK,
		disk = present("disk", context_a.identity),
		resulting_provider_revision = rev(model, main_doc, "1"),
	};
	coherent := observe;
	coherent.disk.provenance.consistency = .{kind = .COHERENT_CAPTURE, provider_namespace = xx NAMESPACE, capture_token = xx "capture"};
	ok, error = submit(model, .[context_a], coherent);
	expect_rejected(model, ok, error, .ADMISSION_DENIED, frontier, "coherent capture without the capability");

	claimed := observe;
	claimed.disk.source_revision = Service.source_revision_of(xx "other");
	ok, error = submit(model, .[context_a], claimed);
	expect_rejected(model, ok, error, .INVALID_ARGUMENT, frontier, "disk revision claim");

	unattributed := observe;
	unattributed.disk.provenance.observation_token = .[];
	ok, error = submit(model, .[context_a], unattributed);
	expect_rejected(model, ok, error, .INVALID_ARGUMENT, frontier, "missing provenance");

	absent := observe;
	absent.disk = .{kind = .ABSENT, provider_revision = observe.resulting_provider_revision, syntax_context = context_a.identity, provenance = provenance()};
	ok, error = submit(model, .[context_a], absent);
	assert(ok, "\e[91mAbsent observation failed: %.\e[0m", error);
	_, selected := selected_text(model, main_doc);
	assert(selected.kind == .ABSENT && selected.selection == .DISK && !selected.source);
	print("Capabilities and limits \e[92mPASS\e[0m\n");
}
