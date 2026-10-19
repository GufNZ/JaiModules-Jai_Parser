#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Pool";
#import "String";

OUTPUT_DIRECTORY :: ".build/dependency_revisions";
COMPILER_VERSION :: #run compiler_get_version_info(null);

Query :: enum {
	CONSTANT;
	SIGNATURE;
	BODY;
	CANDIDATES;
	SCOPE;
	VALUE;
	CALL;
	ANALYSIS;
	LOOKUP;
	LAYOUT;
	LAYOUT_USER;
}

QUERY_COUNT :: #run enum_names(Query).count;

Query_Status :: enum {
	COMPLETE;
	MISSING;
	AMBIGUOUS;
}

Query_Value :: struct {
	status: Query_Status;
	value: s64;
}

Query_Input :: struct {
	revision: s64 = 1;
	identity: s64;
	context_key: s64 = 1;
	literal: s64;
	argument: s64;
	dependency_count: s64;
	targets: [2]Query;
}

World :: struct {
	identity: s64;
	module_revision: s64 = 1;
	inputs: [QUERY_COUNT]Query_Input;
}

Validation_Policy :: enum {
	TRACKED;
	CONSERVATIVE_MODULE;
	PARENT_ONLY;
	UNVALIDATED_DEPENDENCIES;
	IGNORE_SCOPE;
	IGNORE_BODY;
	LATEST_WORLD;
	IGNORE_IDENTITIES;
	SKIP_PARENT_RELATION;
}

Dependency_Link :: struct {
	target: Query;
	target_identity: s64;
	target_context: s64;
	checked_parent_revision: s64;
	observed_dependency_revision: s64;
	value: Query_Value;
}

Query_Result :: struct {
	world_identity: s64;
	module_revision: s64;
	query: Query;
	input: Query_Input;
	revision: s64;
	value: Query_Value;
	links: [2]Dependency_Link;
	computed: bool;
}

Query_Cache :: struct {
	policy: Validation_Policy;
	results: [..]Query_Result;
	next_revision: s64 = 1;
	computations: [QUERY_COUNT]s64;
	reuses: [QUERY_COUNT]s64;
	comparisons: s64;
	link_checks: s64;
	parent_checks: s64;
	stamp_checks: s64;
}

operator == :: (left: Query_Value, right: Query_Value) -> bool {
	return left.status == right.status && left.value == right.value;
}

same_definition :: (left: Query_Input, right: Query_Input) -> bool {
	if (left.identity != right.identity
		|| left.context_key != right.context_key
		|| left.literal != right.literal
		|| left.argument != right.argument
		|| left.dependency_count != right.dependency_count
	) {
		return false;
	}


	for 0..left.dependency_count - 1 {
		if left.targets[it] != right.targets[it] {
			return false;
		}
	}

	return true;
}

compute_value :: (query: Query, input: Query_Input, dependencies: [2]Query_Value) -> Query_Value {
	for 0..input.dependency_count - 1 {
		if dependencies[it].status != .COMPLETE {
			return dependencies[it];
		}
	}


	if query == {
		case .VALUE;
			return ifx input.dependency_count
				then Query_Value.{value = dependencies[0].value + input.argument}
				else Query_Value.{status = .MISSING};

		case .CALL;
			if !dependencies[1].value {
				return .{status = .MISSING};
			}


			return ifx dependencies[1].value <= 2
				then Query_Value.{value = dependencies[0].value * 10 + dependencies[1].value}
				else Query_Value.{status = .AMBIGUOUS};

		case .ANALYSIS;
			return .{value = dependencies[0].value + input.argument};

		case .LOOKUP;
			return ifx input.dependency_count && dependencies[0].value
				then dependencies[0]
				else Query_Value.{status = .MISSING};

		case .LAYOUT;
			return .{value = dependencies[0].value * 8};

		case .LAYOUT_USER;
			return .{value = dependencies[0].value + 8};

		case;
			return .{value = input.literal};
	}
}

evaluate_fresh :: (world: *World, query: Query) -> Query_Value {
	input := world.inputs[query.(s64)];
	dependencies: [2]Query_Value;
	for 0..input.dependency_count - 1 {
		dependencies[it] = evaluate_fresh(world, input.targets[it]);
	}

	return compute_value(query, input, dependencies);
}

evaluate_cached :: (cache: *Query_Cache, world: *World, query: Query) -> Query_Result {
	index := query.(s64);
	input := world.inputs[index];
	previous: Query_Result;
	found := false;
	for 0..cache.results.count - 1 {
		candidate := cache.results[cache.results.count - 1 - it];
		if candidate.query != query {
			continue;
		}


		if cache.policy == .LATEST_WORLD {
			return candidate;
		}

		if candidate.world_identity == world.identity {
			return candidate;
		}

		if !found {
			previous = candidate;
			found = true;
		}
	}

	if (found
		&& (cache.policy == .PARENT_ONLY && previous.input.revision == input.revision
			|| cache.policy == .SKIP_PARENT_RELATION && previous.input.revision != input.revision
		)
	) {
		return previous;
	}


	parent_changed := !found
		|| previous.input.revision != input.revision
		|| (cache.policy != .IGNORE_IDENTITIES
			&& (previous.input.identity != input.identity || previous.input.context_key != input.context_key)
		);
	regenerate := !found;
	if parent_changed {
		cache.parent_checks += 1;
		regenerate = !found || !same_definition(previous.input, input);
	}

	if cache.policy == .CONSERVATIVE_MODULE && found && previous.module_revision != world.module_revision {
		regenerate = true;
	}

	dependencies: [2]Query_Value;
	links: [2]Dependency_Link;
	for 0..input.dependency_count - 1 {
		target := input.targets[it];
		dependency: Query_Result;
		use_unvalidated := found
			&& (cache.policy == .UNVALIDATED_DEPENDENCIES
				|| cache.policy == .IGNORE_SCOPE && (query == .LOOKUP || query == .CALL && it == 1)
				|| cache.policy == .IGNORE_BODY && query == .ANALYSIS
			);
		have_dependency := false;
		if use_unvalidated {
			for candidate: cache.results {
				if candidate.query == target {
					dependency = candidate;
					have_dependency = true;
				}
			}
		}

		if !have_dependency {
			dependency = evaluate_cached(cache, world, target);
		}

		dependencies[it] = dependency.value;
		links[it] = .{
			target = target,
			target_identity = dependency.input.identity,
			target_context = dependency.input.context_key,
			checked_parent_revision = input.revision,
			observed_dependency_revision = dependency.revision,
			value = dependency.value
		};

		cache.link_checks += 1;
		if (found
			&& (it >= previous.input.dependency_count
				|| previous.links[it].target != target
				|| previous.links[it].target_identity != dependency.input.identity
				|| previous.links[it].target_context != dependency.input.context_key
				|| previous.links[it].observed_dependency_revision != dependency.revision && previous.links[it].value != dependency.value
			)
		) {
			regenerate = true;
		}
	}

	value := previous.value;
	revision := previous.revision;
	if regenerate {
		value = compute_value(query, input, dependencies);
		cache.computations[index] += 1;
		revision = cache.next_revision;
		cache.next_revision += 1;
	} else {
		cache.reuses[index] += 1;
		if query.(s64) < Query.VALUE.(s64) && previous.input.revision != input.revision {
			revision = cache.next_revision;
			cache.next_revision += 1;
		}
	}

	result := Query_Result.{
		world_identity = world.identity,
		module_revision = world.module_revision,
		query = query,
		input = input,
		revision = revision,
		value = value,
		links = links,
		computed = regenerate
	};

	array_add(*cache.results, result);
	return result;
}

make_world :: (identity: s64) -> World {
	world := World.{identity = identity};
	for 0..QUERY_COUNT - 1 {
		world.inputs[it] = .{identity = it + 1};
	}

	world.inputs[Query.CONSTANT.(s64)].literal = 3;
	world.inputs[Query.SIGNATURE.(s64)].literal = 64;
	world.inputs[Query.BODY.(s64)].literal = 5;
	world.inputs[Query.CANDIDATES.(s64)].literal = 1;
	world.inputs[Query.VALUE.(s64)].dependency_count = 1;
	world.inputs[Query.VALUE.(s64)].targets[0] = .CONSTANT;
	world.inputs[Query.VALUE.(s64)].argument = 1;
	world.inputs[Query.CALL.(s64)].dependency_count = 2;
	world.inputs[Query.CALL.(s64)].targets = .[.SIGNATURE, .CANDIDATES];
	world.inputs[Query.ANALYSIS.(s64)].dependency_count = 1;
	world.inputs[Query.ANALYSIS.(s64)].targets[0] = .BODY;
	world.inputs[Query.LOOKUP.(s64)].dependency_count = 1;
	world.inputs[Query.LOOKUP.(s64)].targets[0] = .SCOPE;
	world.inputs[Query.LAYOUT.(s64)].dependency_count = 1;
	world.inputs[Query.LAYOUT.(s64)].targets[0] = .VALUE;
	world.inputs[Query.LAYOUT_USER.(s64)].dependency_count = 1;
	world.inputs[Query.LAYOUT_USER.(s64)].targets[0] = .LAYOUT;
	return world;
}

check_world :: (cache: *Query_Cache, world: *World) {
	for 0..QUERY_COUNT - 1 {
		query := it.(Query);
		actual := evaluate_cached(cache, world, query);
		expected := evaluate_fresh(world, query);
		assert(actual.value == expected, "E7 mismatch: world %, query %", world.identity, query);
		assert(actual.world_identity == world.identity && actual.module_revision == world.module_revision);
		assert(actual.input.revision == world.inputs[it].revision);
		assert(same_definition(actual.input, world.inputs[it]));
		for 0..actual.input.dependency_count - 1 {
			link := actual.links[it];
			dependency := evaluate_cached(cache, world, actual.input.targets[it]);
			assert(link.target == actual.input.targets[it]);
			assert(link.checked_parent_revision == actual.input.revision);
			assert(link.observed_dependency_revision == dependency.revision);
			assert(link.target_identity == dependency.input.identity);
			assert(link.target_context == dependency.input.context_key);
			assert(link.value == dependency.value);
			cache.stamp_checks += 1;
		}

		cache.comparisons += 1;
	}
}

Revision_Change :: enum {
	UNCHANGED;
	PARENT_ONLY;
	PARENT_RETARGET;
	PARENT_ARGUMENT;
	DEPENDENCY_ONLY;
	BODY_ONLY;
	SAME_SIGNATURE;
	NEW_OVERLOAD;
	AMBIGUOUS_OVERLOAD;
	REMOVED_OVERLOADS;
	MISSING_NAME_APPEARS;
	NAME_REMOVED;
	ABSENT_LINK_APPEARS;
	DEPENDENCY_IDENTITY;
	DEPENDENCY_IDENTITY_SAME_VALUE;
	PARENT_IDENTITY;
	CONTEXT;
	SIGNATURE;
	TRANSITIVE_LAYOUT;
	SAME_BODY;
	BOTH;
	PARENT_LINK_REMOVED;
	SAME_CONSTANT;
}

Scenario :: struct {
	name: string;
	change: Revision_Change;
	expected_computations: []Query;
	focus: Query = .VALUE;
	expected_value: Query_Value = .{value = 4};
}

SCENARIOS :: Scenario.[
	.{
		name = "unchanged_world",
		change = .UNCHANGED
	},
	.{
		name = "parent_only",
		change = .PARENT_ONLY
	},
	.{
		name = "parent_retarget",
		change = .PARENT_RETARGET,
		expected_computations = Query.[.VALUE, .LAYOUT, .LAYOUT_USER],
		expected_value = .{value = 6}
	},
	.{
		name = "parent_argument",
		change = .PARENT_ARGUMENT,
		expected_computations = Query.[.VALUE, .LAYOUT, .LAYOUT_USER],
		expected_value = .{value = 7}
	},
	.{
		name = "dependency_only",
		change = .DEPENDENCY_ONLY,
		expected_computations = Query.[.CONSTANT, .VALUE, .LAYOUT, .LAYOUT_USER],
		expected_value = .{value = 10}
	},
	.{
		name = "body_only",
		change = .BODY_ONLY,
		expected_computations = Query.[.BODY, .ANALYSIS],
		focus = .ANALYSIS,
		expected_value = .{value = 8}
	},
	.{
		name = "same_signature_new_revision",
		change = .SAME_SIGNATURE,
		focus = .CALL,
		expected_value = .{value = 641}
	},
	.{
		name = "new_overload",
		change = .NEW_OVERLOAD,
		expected_computations = Query.[.CANDIDATES, .CALL],
		focus = .CALL,
		expected_value = .{value = 642}
	},
	.{
		name = "ambiguous_overload",
		change = .AMBIGUOUS_OVERLOAD,
		expected_computations = Query.[.CANDIDATES, .CALL],
		focus = .CALL,
		expected_value = .{status = .AMBIGUOUS}
	},
	.{
		name = "removed_overloads",
		change = .REMOVED_OVERLOADS,
		expected_computations = Query.[.CANDIDATES, .CALL],
		focus = .CALL,
		expected_value = .{status = .MISSING}
	},
	.{
		name = "previously_missing_name",
		change = .MISSING_NAME_APPEARS,
		expected_computations = Query.[.SCOPE, .LOOKUP],
		focus = .LOOKUP,
		expected_value = .{value = 77}
	},
	.{
		name = "name_removed",
		change = .NAME_REMOVED,
		expected_computations = Query.[.SCOPE, .LOOKUP],
		focus = .LOOKUP,
		expected_value = .{status = .MISSING}
	},
	.{
		name = "absent_link_appears",
		change = .ABSENT_LINK_APPEARS,
		expected_computations = Query.[.SCOPE, .LOOKUP],
		focus = .LOOKUP,
		expected_value = .{value = 77}
	},
	.{
		name = "dependency_identity_same_revision",
		change = .DEPENDENCY_IDENTITY,
		expected_computations = Query.[.CONSTANT, .VALUE, .LAYOUT, .LAYOUT_USER],
		expected_value = .{value = 10}
	},
	.{
		name = "dependency_identity_same_value",
		change = .DEPENDENCY_IDENTITY_SAME_VALUE,
		expected_computations = Query.[.CONSTANT, .VALUE]
	},
	.{
		name = "parent_identity_same_revision",
		change = .PARENT_IDENTITY,
		expected_computations = Query.[.VALUE, .LAYOUT, .LAYOUT_USER],
		expected_value = .{value = 7}
	},
	.{
		name = "context_same_revision",
		change = .CONTEXT,
		expected_computations = Query.[.CONSTANT, .VALUE, .LAYOUT, .LAYOUT_USER],
		expected_value = .{value = 10}
	},
	.{
		name = "signature_changed",
		change = .SIGNATURE,
		expected_computations = Query.[.SIGNATURE, .CALL],
		focus = .CALL,
		expected_value = .{value = 321}
	},
	.{
		name = "transitive_constant_layout",
		change = .TRANSITIVE_LAYOUT,
		expected_computations = Query.[.CONSTANT, .VALUE, .LAYOUT, .LAYOUT_USER],
		focus = .LAYOUT_USER,
		expected_value = .{value = 88}
	},
	.{
		name = "same_body_new_revision",
		change = .SAME_BODY,
		focus = .ANALYSIS,
		expected_value = .{value = 5}
	},
	.{
		name = "parent_and_dependency",
		change = .BOTH,
		expected_computations = Query.[.CONSTANT, .VALUE, .LAYOUT, .LAYOUT_USER],
		expected_value = .{value = 13}
	},
	.{
		name = "parent_link_removed",
		change = .PARENT_LINK_REMOVED,
		expected_computations = Query.[.VALUE, .LAYOUT, .LAYOUT_USER],
		expected_value = .{status = .MISSING}
	},
	.{
		name = "same_constant_new_revision",
		change = .SAME_CONSTANT
	}
];

make_scenario_worlds :: (change: Revision_Change) -> (World, World) {
	initial := make_world(1);
	if change == {
		case .NAME_REMOVED;
			initial.inputs[Query.SCOPE.(s64)].literal = 77;

		case .ABSENT_LINK_APPEARS;
			initial.inputs[Query.LOOKUP.(s64)].dependency_count = 0;
	}

	changed := initial;
	changed.identity = 2;
	if change != .UNCHANGED {
		changed.module_revision += 1;
	}

	if change == {
		case .PARENT_ONLY;
			changed.inputs[Query.VALUE.(s64)].revision += 1;

		case .PARENT_RETARGET;
			changed.inputs[Query.VALUE.(s64)].revision += 1;
			changed.inputs[Query.VALUE.(s64)].targets[0] = .BODY;

		case .PARENT_ARGUMENT;
			changed.inputs[Query.VALUE.(s64)].revision += 1;
			changed.inputs[Query.VALUE.(s64)].argument = 4;

		case .DEPENDENCY_ONLY; #through;
		case .TRANSITIVE_LAYOUT;
			changed.inputs[Query.CONSTANT.(s64)].revision += 1;
			changed.inputs[Query.CONSTANT.(s64)].literal = 9;

		case .BODY_ONLY;
			changed.inputs[Query.BODY.(s64)].revision += 1;
			changed.inputs[Query.BODY.(s64)].literal = 8;

		case .SAME_SIGNATURE;
			changed.inputs[Query.SIGNATURE.(s64)].revision += 1;

		case .NEW_OVERLOAD;
			changed.inputs[Query.CANDIDATES.(s64)].revision += 1;
			changed.inputs[Query.CANDIDATES.(s64)].literal = 2;

		case .AMBIGUOUS_OVERLOAD;
			changed.inputs[Query.CANDIDATES.(s64)].revision += 1;
			changed.inputs[Query.CANDIDATES.(s64)].literal = 3;

		case .REMOVED_OVERLOADS;
			changed.inputs[Query.CANDIDATES.(s64)].revision += 1;
			changed.inputs[Query.CANDIDATES.(s64)].literal = 0;

		case .MISSING_NAME_APPEARS;
			changed.inputs[Query.SCOPE.(s64)].revision += 1;
			changed.inputs[Query.SCOPE.(s64)].literal = 77;

		case .NAME_REMOVED;
			changed.inputs[Query.SCOPE.(s64)].revision += 1;
			changed.inputs[Query.SCOPE.(s64)].literal = 0;

		case .ABSENT_LINK_APPEARS;
			changed.inputs[Query.LOOKUP.(s64)].revision += 1;
			changed.inputs[Query.LOOKUP.(s64)].dependency_count = 1;
			changed.inputs[Query.SCOPE.(s64)].revision += 1;
			changed.inputs[Query.SCOPE.(s64)].literal = 77;

		case .DEPENDENCY_IDENTITY;
			changed.inputs[Query.CONSTANT.(s64)].identity += 1000;
			changed.inputs[Query.CONSTANT.(s64)].literal = 9;

		case .DEPENDENCY_IDENTITY_SAME_VALUE;
			changed.inputs[Query.CONSTANT.(s64)].identity += 1000;

		case .PARENT_IDENTITY;
			changed.inputs[Query.VALUE.(s64)].identity += 1000;
			changed.inputs[Query.VALUE.(s64)].argument = 4;

		case .CONTEXT;
			changed.inputs[Query.CONSTANT.(s64)].context_key += 1;
			changed.inputs[Query.CONSTANT.(s64)].literal = 9;

		case .SIGNATURE;
			changed.inputs[Query.SIGNATURE.(s64)].revision += 1;
			changed.inputs[Query.SIGNATURE.(s64)].literal = 32;

		case .SAME_BODY;
			changed.inputs[Query.BODY.(s64)].revision += 1;

		case .BOTH;
			changed.inputs[Query.VALUE.(s64)].revision += 1;
			changed.inputs[Query.VALUE.(s64)].argument = 4;
			changed.inputs[Query.CONSTANT.(s64)].revision += 1;
			changed.inputs[Query.CONSTANT.(s64)].literal = 9;

		case .PARENT_LINK_REMOVED;
			changed.inputs[Query.VALUE.(s64)].revision += 1;
			changed.inputs[Query.VALUE.(s64)].dependency_count = 0;

		case .SAME_CONSTANT;
			changed.inputs[Query.CONSTANT.(s64)].revision += 1;
	}

	return initial, changed;
}

freeze_results :: (results: []Query_Result) -> string {
	builder: String_Builder;
	for result: results {
		print(
			*builder,
			"% % % % % % % % % % % % % %\n",
			result.world_identity,
			result.module_revision,
			result.query,
			result.input.revision,
			result.input.identity,
			result.input.context_key,
			result.input.literal,
			result.input.argument,
			result.input.dependency_count,
			result.input.targets,
			result.revision,
			result.value.status,
			result.value.value,
			result.computed
		);

		for link: result.links {
			print(
				*builder,
				"% % % % % % %\n",
				link.target,
				link.target_identity,
				link.target_context,
				link.checked_parent_revision,
				link.observed_dependency_revision,
				link.value.status,
				link.value.value
			);
		}
	}

	return builder_to_string(*builder);
}

Experiment_Audit :: struct {
	scenarios: s64;
	comparisons: s64;
	stamp_checks: s64;
	tracked_computations: s64;
	coarse_computations: s64;
	old_world_checks: s64;
	negative_controls: s64;
}

save_cache_trace :: (
	name: string,
	cache: *Query_Cache,
	results: *String_Builder,
	links: *String_Builder
) {
	for result: cache.results {
		print(
			results,
			"%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\n",
			name,
			cache.policy,
			result.world_identity,
			result.module_revision,
			result.query,
			result.input.identity,
			result.input.context_key,
			result.input.revision,
			result.revision,
			result.value.status,
			result.value.value,
			result.computed
		);

		for 0..result.input.dependency_count - 1 {
			link := result.links[it];
			print(
				links,
				"%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\n",
				name,
				cache.policy,
				result.world_identity,
				result.query,
				result.input.identity,
				result.input.context_key,
				link.checked_parent_revision,
				link.target,
				link.target_identity,
				link.target_context,
				link.observed_dependency_revision,
				link.value.value
			);
		}
	}
}

run_scenario :: (
	scenario: Scenario,
	summary: *String_Builder,
	results: *String_Builder,
	links: *String_Builder,
	audit: *Experiment_Audit
) {
	initial, changed := make_scenario_worlds(scenario.change);
	tracked: Query_Cache;
	coarse := Query_Cache.{policy = .CONSERVATIVE_MODULE};
	defer array_free(tracked.results);
	defer array_free(coarse.results);

	check_world(*tracked, *initial);
	check_world(*coarse, *initial);
	initial_results := freeze_results(tracked.results);
	defer free(initial_results);

	before := tracked.computations;
	coarse_before := coarse.computations;
	check_world(*tracked, *initial);
	check_world(*coarse, *initial);
	assert(tracked.results.count == QUERY_COUNT && coarse.results.count == QUERY_COUNT);
	for 0..QUERY_COUNT - 1 {
		assert(tracked.computations[it] == before[it] && before[it] == 1);
		assert(coarse.computations[it] == coarse_before[it] && coarse_before[it] == 1);
	}

	actual := evaluate_cached(*tracked, *changed, scenario.focus);
	assert(actual.value == scenario.expected_value, "E7 authored expectation: %", scenario.name);
	check_world(*tracked, *changed);
	check_world(*coarse, *changed);
	tracked_delta: s64;
	coarse_delta: s64;
	for 0..QUERY_COUNT - 1 {
		query := it.(Query);
		expected := false;
		for candidate: scenario.expected_computations {
			if query == candidate {
				expected = true;
			}
		}

		delta := tracked.computations[it] - before[it];
		assert(delta == expected.(s64), "E7 reuse mismatch: % / %", scenario.name, query);
		tracked_delta += delta;
		coarse_change := coarse.computations[it] - coarse_before[it];
		assert(coarse_change == (scenario.change != .UNCHANGED).(s64));
		coarse_delta += coarse_change;
	}

	assert(tracked.results.count == QUERY_COUNT * 2 && coarse.results.count == QUERY_COUNT * 2);
	retained: []Query_Result = .{QUERY_COUNT, tracked.results.data};
	unchanged := freeze_results(retained);
	defer free(unchanged);

	assert(unchanged == initial_results);
	after := tracked.computations;
	coarse_after := coarse.computations;
	check_world(*tracked, *initial);
	check_world(*tracked, *changed);
	check_world(*coarse, *initial);
	check_world(*coarse, *changed);
	for 0..QUERY_COUNT - 1 {
		assert(tracked.computations[it] == after[it]);
		assert(coarse.computations[it] == coarse_after[it]);
	}

	audit.scenarios += 1;
	audit.comparisons += tracked.comparisons + coarse.comparisons;
	audit.stamp_checks += tracked.stamp_checks + coarse.stamp_checks;
	audit.tracked_computations += tracked_delta;
	audit.coarse_computations += coarse_delta;
	audit.old_world_checks += 2;
	save_cache_trace(scenario.name, *tracked, results, links);
	save_cache_trace(scenario.name, *coarse, results, links);
	print(
		summary,
		"%\t%\t%\t%\t%\t%\n",
		scenario.name,
		tracked_delta,
		coarse_delta,
		scenario.focus,
		actual.value.status,
		actual.value.value
	);

	print("E7 %: tracked %, conservative % recomputations.\n", scenario.name, tracked_delta, coarse_delta);
}

Negative_Control :: struct {
	policy: Validation_Policy;
	change: Revision_Change;
	focus: Query;
	request_old: bool;
}

NEGATIVE_CONTROLS :: Negative_Control.[
	.{
		policy = .PARENT_ONLY,
		change = .DEPENDENCY_ONLY,
		focus = .VALUE
	},
	.{
		policy = .UNVALIDATED_DEPENDENCIES,
		change = .TRANSITIVE_LAYOUT,
		focus = .LAYOUT_USER
	},
	.{
		policy = .IGNORE_SCOPE,
		change = .NEW_OVERLOAD,
		focus = .CALL
	},
	.{
		policy = .IGNORE_SCOPE,
		change = .MISSING_NAME_APPEARS,
		focus = .LOOKUP
	},
	.{
		policy = .IGNORE_BODY,
		change = .BODY_ONLY,
		focus = .ANALYSIS
	},
	.{
		policy = .IGNORE_IDENTITIES,
		change = .DEPENDENCY_IDENTITY,
		focus = .VALUE
	},
	.{
		policy = .IGNORE_IDENTITIES,
		change = .CONTEXT,
		focus = .VALUE
	},
	.{
		policy = .SKIP_PARENT_RELATION,
		change = .PARENT_RETARGET,
		focus = .VALUE
	},
	.{
		policy = .SKIP_PARENT_RELATION,
		change = .ABSENT_LINK_APPEARS,
		focus = .LOOKUP
	},
	.{
		policy = .SKIP_PARENT_RELATION,
		change = .PARENT_LINK_REMOVED,
		focus = .VALUE
	},
	.{
		policy = .LATEST_WORLD,
		change = .DEPENDENCY_ONLY,
		focus = .VALUE,
		request_old = true
	}
];

run_negative_controls :: (summary: *String_Builder, audit: *Experiment_Audit) {
	for control: NEGATIVE_CONTROLS {
		initial, changed := make_scenario_worlds(control.change);
		cache: Query_Cache;
		defer array_free(cache.results);

		check_world(*cache, *initial);
		if control.request_old {
			check_world(*cache, *changed);
		}

		cache.policy = control.policy;
		requested := ifx control.request_old
			then *initial
			else *changed;

		expected := evaluate_fresh(requested, control.focus);
		actual := evaluate_cached(*cache, requested, control.focus);
		assert(actual.value != expected, "E7 failed to expose bad policy %", control.policy);
		audit.negative_controls += 1;
		print(
			summary,
			"%\t%\t%\t%\t%\t%\t%\t%\n",
			control.policy,
			control.change,
			control.focus,
			requested.identity,
			expected.status,
			expected.value,
			actual.value.status,
			actual.value.value
		);
	}
}

write_output :: (name: string, builder: *String_Builder) {
	text := builder_to_string(builder);
	defer free(text);

	assert(write_entire_file(tprint("%/%", OUTPUT_DIRECTORY, name), text));
}

main :: () {
	assert(make_directory_if_it_does_not_exist(".build"));
	assert(make_directory_if_it_does_not_exist(OUTPUT_DIRECTORY));
	defer reset_temporary_storage();

	summary: String_Builder;
	results: String_Builder;
	links: String_Builder;
	controls: String_Builder;
	defer reset(*summary);
	defer reset(*results);
	defer reset(*links);
	defer reset(*controls);

	print(*summary, "case\ttracked_computations\tcoarse_computations\tfocus\tstatus\tvalue\n");
	print(*results, "case\tpolicy\tworld\tmodule_revision\tquery\towner\tcontext\tparent_revision\tresult_revision\tstatus\tvalue\tcomputed\n");
	print(*links, "case\tpolicy\tworld\tquery\towner\tcontext\tchecked_parent_revision\ttarget\ttarget_owner\ttarget_context\tobserved_dependency_revision\tvalue\n");
	print(*controls, "policy\tchange\tfocus\tworld\texpected_status\texpected_value\tstale_status\tstale_value\n");
	audit: Experiment_Audit;
	for scenario: SCENARIOS {
		run_scenario(scenario, *summary, *results, *links, *audit);
	}

	run_negative_controls(*controls, *audit);
	assert(audit.scenarios == SCENARIOS.count);
	assert(audit.negative_controls == NEGATIVE_CONTROLS.count);
	write_output("summary.tsv", *summary);
	write_output("results.tsv", *results);
	write_output("links.tsv", *links);
	write_output("negative_controls.tsv", *controls);
	assert(write_entire_file(tprint("%/compiler_version.txt", OUTPUT_DIRECTORY), COMPILER_VERSION));
	audit_json := tprint(
		"{\"scenarios\":%,\"queries\":%,\"fresh_comparisons\":%,\"stamp_checks\":%,\"tracked_computations\":%,\"coarse_computations\":%,\"old_world_checks\":%,\"negative_controls\":%}\n",
		audit.scenarios,
		QUERY_COUNT,
		audit.comparisons,
		audit.stamp_checks,
		audit.tracked_computations,
		audit.coarse_computations,
		audit.old_world_checks,
		audit.negative_controls
	);

	assert(write_entire_file(tprint("%/audit_summary.json", OUTPUT_DIRECTORY), audit_json));
	print(
		"E7 complete: % scenarios, % fresh comparisons, % stamp checks, % negative controls.\n",
		audit.scenarios,
		audit.comparisons,
		audit.stamp_checks,
		audit.negative_controls
	);
}
