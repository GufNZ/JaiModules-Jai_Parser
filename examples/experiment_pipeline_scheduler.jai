#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "String";

OUTPUT_DIRECTORY :: ".build/pipeline_scheduler";
COMPILER_VERSION :: #run compiler_get_version_info(null);
TASK_LIMIT :: 16;
REQUEST_LIMIT :: 16;

Milestone :: enum {
	SIGNATURE;
	BODY;
	LAYOUT;
	EXTERNAL;
}

Outcome :: enum {
	PENDING;
	AVAILABLE;
	CYCLE;
	FAILED;
	UNSUPPORTED;
	CANCELLED;
	SHUTDOWN;
}

Policy :: enum {
	CORRECT;
	STALL_IS_CYCLE;
	CANCEL_SHARED;
	WORLD_BLIND;
	DECLARATION_BARRIER;
	DOUBLE_NOTIFY;
	ACCEPT_LATE;
	NO_CYCLES;
	POINTER_NEEDS_LAYOUT;
}

Task :: struct {
	world: s64;
	declaration: s64;
	milestone: Milestone;
	dependencies: [4]s64;
	dependency_count: s64;
	outcome: Outcome;
	value: s64;
	token: s64;
	runs: s64;
	published_at: s64;
	cycle_group: s64;
	blocked_by: s64 = -1;
}

Request :: struct {
	world: s64;
	task: s64 = -1;
	outcome: Outcome;
	value: s64;
	pending_on_return: bool;
	notifications: s64;
}

Scheduler :: struct {
	policy: Policy;
	tasks: [TASK_LIMIT]Task;
	task_count: s64;
	requests: [REQUEST_LIMIT]Request;
	request_count: s64;
	current_world: s64 = 1;
	tick: s64;
	reverse: bool;
	closed: bool;
	checks: s64;
}

add_task :: (
	scheduler: *Scheduler,
	world: s64,
	declaration: s64,
	milestone: Milestone,
	value: s64 = 1
) -> s64 {
	assert(scheduler.task_count < TASK_LIMIT && !scheduler.closed);
	for 0..scheduler.task_count - 1 {
		task := scheduler.tasks[it];
		assert(task.world != world || task.declaration != declaration || task.milestone != milestone);
	}

	index := scheduler.task_count;
	scheduler.task_count += 1;
	scheduler.tasks[index] = .{
		world = world,
		declaration = declaration,
		milestone = milestone,
		value = value,
		token = index + 1
	};

	return index;
}

depends_on :: (scheduler: *Scheduler, parent: s64, target: s64) {
	assert(parent >= 0 && parent < scheduler.task_count && target >= 0 && target < scheduler.task_count);
	task := *scheduler.tasks[parent];
	assert(task.outcome == .PENDING && task.dependency_count < task.dependencies.count);
	assert(task.world == scheduler.tasks[target].world);
	task.dependencies[task.dependency_count] = target;
	task.dependency_count += 1;
}

request_task :: (
	scheduler: *Scheduler,
	world: s64,
	declaration: s64,
	milestone: Milestone
) -> s64 {
	assert(scheduler.request_count < REQUEST_LIMIT);
	request := Request.{world = world, outcome = .UNSUPPORTED};
	if scheduler.closed {
		request.outcome = .SHUTDOWN;
	} else {
		for 0..scheduler.task_count - 1 {
			task := scheduler.tasks[it];
			if ((task.world == world || scheduler.policy == .WORLD_BLIND)
				&& task.declaration == declaration && task.milestone == milestone
			) {
				request.task = it;
				request.outcome = task.outcome;
				request.value = ifx task.outcome == .AVAILABLE then task.value;
				request.pending_on_return = task.outcome == .PENDING;
				break;
			}
		}
	}

	index := scheduler.request_count;
	scheduler.requests[index] = request;
	scheduler.request_count += 1;
	return index;
}

notify_waiters :: (scheduler: *Scheduler) {
	for 0..scheduler.request_count - 1 {
		request := *scheduler.requests[it];
		if (request.task >= 0
			&& (request.outcome == .PENDING
				|| scheduler.policy == .DOUBLE_NOTIFY && request.outcome == .AVAILABLE
			)
		) {
			task := scheduler.tasks[request.task];
			if task.outcome != .PENDING {
				request.outcome = task.outcome;
				request.value = task.value;
				request.notifications += 1;
			}
		}
	}
}

advance :: (scheduler: *Scheduler) -> bool {
	scheduler.tick += 1;
	progress := false;
	for 0..scheduler.task_count - 1 {
		index := ifx scheduler.reverse
			then scheduler.task_count - 1 - it
			else it;

		task := *scheduler.tasks[index];
		if task.outcome != .PENDING || task.milestone == .EXTERNAL {
			continue;
		}


		ready := true;
		failed := false;
		value := task.value;
		if scheduler.policy == .DECLARATION_BARRIER {
			for 0..scheduler.task_count - 1 {
				other := scheduler.tasks[it];
				if (it != index
					&& other.world == task.world
					&& other.declaration == task.declaration
					&& other.outcome == .PENDING
				) {
					ready = false;
				}
			}
		}

		for 0..task.dependency_count - 1 {
			dependency := scheduler.tasks[task.dependencies[it]];
			if dependency.outcome != .AVAILABLE {
				ready = false;
				if dependency.outcome != .PENDING {
					failed = true;
					task.blocked_by = task.dependencies[it];
				}
			}

			value += dependency.value;
		}

		if failed {
			task.outcome = .FAILED;
			task.published_at = scheduler.tick;
			progress = true;
		} else if ready {
			task.outcome = .AVAILABLE;
			task.value = value;
			task.runs += 1;
			task.published_at = scheduler.tick;
			progress = true;
		}
	}

	notify_waiters(scheduler);
	return progress;
}

detect_cycles :: (scheduler: *Scheduler) -> bool {
	if scheduler.policy == .NO_CYCLES {
		return false;
	}


	if scheduler.policy == .STALL_IS_CYCLE {
		changed := false;
		for 0..scheduler.task_count - 1 {
			task := *scheduler.tasks[it];
			if task.outcome == .PENDING {
				task.outcome = .CYCLE;
				task.cycle_group = it + 1;
				changed = true;
			}
		}

		return changed;
	}


	reachable: [TASK_LIMIT][TASK_LIMIT]bool;
	for source: 0..scheduler.task_count - 1 {
		task := scheduler.tasks[source];
		if task.outcome != .PENDING {
			continue;
		}


		for 0..task.dependency_count - 1 {
			target := task.dependencies[it];
			if scheduler.tasks[target].outcome == .PENDING {
				reachable[source][target] = true;
			}
		}
	}

	for via: 0..scheduler.task_count - 1 {
		for source: 0..scheduler.task_count - 1 {
			for target: 0..scheduler.task_count - 1 {
				reachable[source][target] = reachable[source][target]
					|| reachable[source][via] && reachable[via][target];
			}
		}
	}

	changed := false;
	for source: 0..scheduler.task_count - 1 {
		if reachable[source][source] {
			task := *scheduler.tasks[source];
			task.outcome = .CYCLE;
			task.cycle_group = source + 1;
			task.published_at = scheduler.tick;
			for target: 0..source - 1 {
				if reachable[source][target] && reachable[target][source] {
					task.cycle_group = Min(task.cycle_group, target + 1);
				}
			}

			changed = true;
		}
	}

	return changed;
}

drain :: (scheduler: *Scheduler) {
	for 0..TASK_LIMIT * 2 {
		if advance(scheduler) {
			continue;
		}


		if !detect_cycles(scheduler) {
			return;
		}


		notify_waiters(scheduler);
	}

	assert(false, "E8 exceeded bounded scheduler steps");
}

cancel_request :: (scheduler: *Scheduler, index: s64) -> bool {
	request := *scheduler.requests[index];
	if request.outcome != .PENDING {
		return false;
	}


	request.outcome = .CANCELLED;
	request.notifications += 1;
	if scheduler.policy == .CANCEL_SHARED {
		scheduler.tasks[request.task].outcome = .CANCELLED;
		notify_waiters(scheduler);
	}

	return true;
}

shutdown :: (scheduler: *Scheduler) {
	scheduler.closed = true;
	for 0..scheduler.task_count - 1 {
		task := *scheduler.tasks[it];
		if task.outcome == .PENDING {
			task.outcome = .SHUTDOWN;
			task.published_at = scheduler.tick;
		}
	}

	notify_waiters(scheduler);
}

complete_external :: (
	scheduler: *Scheduler,
	index: s64,
	token: s64,
	outcome: Outcome,
	value: s64
) -> bool {
	assert(index >= 0 && index < scheduler.task_count);
	assert(outcome == .AVAILABLE || outcome == .FAILED || outcome == .UNSUPPORTED);
	task := *scheduler.tasks[index];
	if (task.milestone != .EXTERNAL
		|| task.token != token
		|| (scheduler.policy != .ACCEPT_LATE && (scheduler.closed || task.outcome != .PENDING))
	) {
		return false;
	}


	task.outcome = outcome;
	task.value = value;
	task.runs += 1;
	task.published_at = scheduler.tick;
	notify_waiters(scheduler);
	return true;
}

Fixture :: struct {
	signature: s64;
	other_signature: s64;
	external: s64;
	body: s64;
	layout: s64;
	other_layout: s64;
	other_body: s64;
}

make_fixture :: (scheduler: *Scheduler) -> Fixture {
	fixture := Fixture.{
		signature		= add_task(scheduler, 1, 1, .SIGNATURE, 2),
		other_signature	= add_task(scheduler, 1, 2, .SIGNATURE, 3),
		external 		= add_task(scheduler, 1, 100, .EXTERNAL),
		body			= add_task(scheduler, 1, 1, .BODY),
		layout			= add_task(scheduler, 1, 1, .LAYOUT, 8),
		other_layout	= add_task(scheduler, 1, 2, .LAYOUT, 8),
		other_body		= add_task(scheduler, 1, 2, .BODY)
	};

	depends_on(scheduler, fixture.body, fixture.signature);
	depends_on(scheduler, fixture.body, fixture.external);
	depends_on(scheduler, fixture.layout, fixture.signature);
	depends_on(scheduler, fixture.other_layout, fixture.other_signature);
	depends_on(scheduler, fixture.other_body, fixture.other_signature);
	return fixture;
}

require :: (scheduler: *Scheduler, condition: bool) {
	assert(condition, "E8 authored expectation failed");
	scheduler.checks += 1;
}

expect_task :: (scheduler: *Scheduler, index: s64, outcome: Outcome, value: s64 = 0) {
	task := scheduler.tasks[index];
	require(scheduler, task.outcome == outcome);
	if outcome == .AVAILABLE {
		require(scheduler, task.value == value && task.runs == 1);
	}
}

finish_external :: (scheduler: *Scheduler, index: s64, outcome: Outcome = .AVAILABLE, value: s64 = 50) {
	require(scheduler, complete_external(scheduler, index, scheduler.tasks[index].token, outcome, value));
	drain(scheduler);
}

is_current :: (scheduler: *Scheduler, request: s64) -> bool {
	result := scheduler.requests[request];
	return result.world == scheduler.current_world && result.outcome == .AVAILABLE;
}

check_invariants :: (scheduler: *Scheduler) {
	for 0..scheduler.task_count - 1 {
		task := scheduler.tasks[it];
		require(scheduler, task.runs >= 0 && task.runs <= 1);

		if task.outcome == {
			case .AVAILABLE;
				if task.milestone != .EXTERNAL {
					for 0..task.dependency_count - 1 {
						dependency := scheduler.tasks[task.dependencies[it]];
						require(scheduler, dependency.outcome == .AVAILABLE && dependency.published_at <= task.published_at);
					}
				}

			case .CYCLE;
				require(scheduler, task.cycle_group > 0 && !task.runs);

			case .FAILED;
				require(scheduler, task.milestone == .EXTERNAL || task.blocked_by >= 0);
		}
	}

	for 0..scheduler.request_count - 1 {
		request := scheduler.requests[it];
		require(scheduler, request.notifications == (request.pending_on_return && request.outcome != .PENDING).(s64));
		if request.task >= 0 {
			task := scheduler.tasks[request.task];
			require(scheduler, task.world == request.world);
			if request.outcome == .AVAILABLE {
				require(scheduler, task.outcome == .AVAILABLE && task.value == request.value);
			}
		}
	}
}

Scenario :: enum {
	MILESTONES;
	POINTER_SELF;
	POINTER_MUTUAL;
	BY_VALUE_SELF;
	BY_VALUE_MUTUAL;
	MUTUAL_CALLS;
	SLOW_EXTERNAL;
	SHARED_CANCEL;
	ALL_CANCEL;
	EXTERNAL_FAILURE;
	EXTERNAL_UNSUPPORTED;
	WORLD_SELECTION;
	SHUTDOWN;
	IMMEDIATE;
	UNKNOWN_MILESTONE;
	REPLAY_EXTERNAL;
	FAILURE_CHAIN;
}

run_scenario :: (scenario: Scenario, reverse: bool) -> Scheduler {
	scheduler := Scheduler.{reverse = reverse};
	fixture := make_fixture(*scheduler);
	waiter := request_task(*scheduler, 1, 1, .BODY);
	require(*scheduler, scheduler.requests[waiter].pending_on_return);
	if scenario == {
		case .POINTER_MUTUAL;
			depends_on(*scheduler, fixture.layout, fixture.other_signature);
			depends_on(*scheduler, fixture.other_layout, fixture.signature);

		case .BY_VALUE_SELF;
			depends_on(*scheduler, fixture.layout, fixture.layout);

		case .BY_VALUE_MUTUAL;
			depends_on(*scheduler, fixture.layout, fixture.other_layout);
			depends_on(*scheduler, fixture.other_layout, fixture.layout);
			depends_on(*scheduler, fixture.other_body, fixture.layout);

		case .MUTUAL_CALLS;
			scheduler.tasks[fixture.body].dependency_count = 1;
			depends_on(*scheduler, fixture.body, fixture.other_signature);
			depends_on(*scheduler, fixture.other_body, fixture.signature);

		case .FAILURE_CHAIN;
			depends_on(*scheduler, fixture.layout, fixture.body);
	}

	drain(*scheduler);
	expect_task(*scheduler, fixture.signature, .AVAILABLE, 2);
	expect_task(*scheduler, fixture.other_signature, .AVAILABLE, 3);

	if scenario == {
		case .MILESTONES;
			expect_task(*scheduler, fixture.layout, .AVAILABLE, 10);
			expect_task(*scheduler, fixture.body, .PENDING);
			finish_external(*scheduler, fixture.external);
			expect_task(*scheduler, fixture.body, .AVAILABLE, 53);

		case .POINTER_SELF;
			expect_task(*scheduler, fixture.layout, .AVAILABLE, 10);
			expect_task(*scheduler, fixture.body, .PENDING);

		case .POINTER_MUTUAL;
			expect_task(*scheduler, fixture.layout, .AVAILABLE, 13);
			expect_task(*scheduler, fixture.other_layout, .AVAILABLE, 13);

		case .BY_VALUE_SELF;
			expect_task(*scheduler, fixture.layout, .CYCLE);
			require(*scheduler, scheduler.tasks[fixture.layout].cycle_group == fixture.layout + 1);
			expect_task(*scheduler, fixture.external, .PENDING);
			expect_task(*scheduler, fixture.body, .PENDING);

		case .BY_VALUE_MUTUAL;
			expect_task(*scheduler, fixture.layout, .CYCLE);
			expect_task(*scheduler, fixture.other_layout, .CYCLE);
			expect_task(*scheduler, fixture.other_body, .FAILED);
			require(*scheduler, scheduler.tasks[fixture.layout].cycle_group == scheduler.tasks[fixture.other_layout].cycle_group);
			expect_task(*scheduler, fixture.external, .PENDING);

		case .MUTUAL_CALLS;
			expect_task(*scheduler, fixture.body, .AVAILABLE, 6);
			expect_task(*scheduler, fixture.other_body, .AVAILABLE, 6);

		case .SLOW_EXTERNAL;
			for 0..2 {
				drain(*scheduler);
				expect_task(*scheduler, fixture.external, .PENDING);
				require(*scheduler, scheduler.requests[waiter].outcome == .PENDING);
			}

			finish_external(*scheduler, fixture.external);
			expect_task(*scheduler, fixture.body, .AVAILABLE, 53);

		case .SHARED_CANCEL;
			other := request_task(*scheduler, 1, 1, .BODY);
			require(*scheduler, scheduler.requests[other].task == scheduler.requests[waiter].task);
			require(*scheduler, cancel_request(*scheduler, waiter));
			require(*scheduler, !cancel_request(*scheduler, waiter));
			finish_external(*scheduler, fixture.external);
			require(*scheduler, scheduler.requests[waiter].outcome == .CANCELLED);
			require(*scheduler, scheduler.requests[other].outcome == .AVAILABLE && scheduler.requests[other].value == 53);
			require(*scheduler, !cancel_request(*scheduler, other));
			expect_task(*scheduler, fixture.body, .AVAILABLE, 53);

		case .ALL_CANCEL;
			other := request_task(*scheduler, 1, 1, .BODY);
			require(*scheduler, cancel_request(*scheduler, waiter));
			require(*scheduler, cancel_request(*scheduler, other));
			expect_task(*scheduler, fixture.body, .PENDING);
			shutdown(*scheduler);
			require(*scheduler, scheduler.requests[waiter].outcome == .CANCELLED && scheduler.requests[other].outcome == .CANCELLED);
			expect_task(*scheduler, fixture.external, .SHUTDOWN);

		case .EXTERNAL_FAILURE;
			finish_external(*scheduler, fixture.external, .FAILED);
			expect_task(*scheduler, fixture.body, .FAILED);
			require(*scheduler, scheduler.requests[waiter].outcome == .FAILED);

		case .EXTERNAL_UNSUPPORTED;
			external_waiter := request_task(*scheduler, 1, 100, .EXTERNAL);
			finish_external(*scheduler, fixture.external, .UNSUPPORTED);
			expect_task(*scheduler, fixture.body, .FAILED);
			require(*scheduler, scheduler.requests[external_waiter].outcome == .UNSUPPORTED);

		case .WORLD_SELECTION;
			new_signature := add_task(*scheduler, 2, 1, .SIGNATURE, 12);
			new_external := add_task(*scheduler, 2, 100, .EXTERNAL);
			new_body := add_task(*scheduler, 2, 1, .BODY);
			depends_on(*scheduler, new_body, new_signature);
			depends_on(*scheduler, new_body, new_external);
			scheduler.current_world = 2;
			current := request_task(*scheduler, 2, 1, .BODY);
			require(*scheduler, scheduler.requests[current].task != scheduler.requests[waiter].task);
			finish_external(*scheduler, fixture.external);
			require(*scheduler, !is_current(*scheduler, waiter) && !is_current(*scheduler, current));
			retained := scheduler.tasks[fixture.body];
			finish_external(*scheduler, new_external, .AVAILABLE, 60);
			require(*scheduler, is_current(*scheduler, current) && scheduler.requests[current].value == 73);
			require(*scheduler, scheduler.requests[waiter].value == 53);
			require(*scheduler, retained.value == scheduler.tasks[fixture.body].value && retained.published_at == scheduler.tasks[fixture.body].published_at);
			old := request_task(*scheduler, 1, 1, .BODY);
			require(*scheduler, scheduler.requests[old].value == 53 && !scheduler.requests[old].pending_on_return);

		case .SHUTDOWN;
			shutdown(*scheduler);
			shutdown(*scheduler);
			expect_task(*scheduler, fixture.body, .SHUTDOWN);
			require(*scheduler, scheduler.requests[waiter].outcome == .SHUTDOWN);
			require(*scheduler, !complete_external(*scheduler, fixture.external, scheduler.tasks[fixture.external].token, .AVAILABLE, 50));
			late := request_task(*scheduler, 1, 1, .SIGNATURE);
			require(*scheduler, scheduler.requests[late].outcome == .SHUTDOWN && !scheduler.requests[late].pending_on_return);
			expect_task(*scheduler, fixture.signature, .AVAILABLE, 2);

		case .IMMEDIATE;
			immediate := request_task(*scheduler, 1, 1, .SIGNATURE);
			require(*scheduler, scheduler.requests[immediate].outcome == .AVAILABLE && scheduler.requests[immediate].value == 2);
			require(*scheduler, !scheduler.requests[immediate].pending_on_return && !scheduler.requests[immediate].notifications);

		case .UNKNOWN_MILESTONE;
			unknown := request_task(*scheduler, 1, 999, .LAYOUT);
			require(*scheduler, scheduler.requests[unknown].outcome == .UNSUPPORTED && !scheduler.requests[unknown].pending_on_return);

		case .REPLAY_EXTERNAL;
			require(*scheduler, !complete_external(*scheduler, fixture.external, scheduler.tasks[fixture.external].token + 1, .AVAILABLE, 50));
			expect_task(*scheduler, fixture.external, .PENDING);
			finish_external(*scheduler, fixture.external);
			require(*scheduler, !complete_external(*scheduler, fixture.external, scheduler.tasks[fixture.external].token, .AVAILABLE, 999));
			expect_task(*scheduler, fixture.body, .AVAILABLE, 53);
			expect_task(*scheduler, fixture.external, .AVAILABLE, 50);

		case .FAILURE_CHAIN;
			finish_external(*scheduler, fixture.external, .FAILED);
			expect_task(*scheduler, fixture.body, .FAILED);
			expect_task(*scheduler, fixture.layout, .FAILED);
			expect_task(*scheduler, fixture.other_body, .AVAILABLE, 4);
	}

	drain(*scheduler);
	check_invariants(*scheduler);
	return scheduler;
}

Audit :: struct {
	scenarios: s64;
	order_runs: s64;
	expectation_checks: s64;
	order_checks: s64;
	task_records: s64;
	request_records: s64;
	dependency_records: s64;
	negative_controls: s64;
}

completion_snapshot :: (scheduler: *Scheduler) -> string {
	builder: String_Builder;
	print(*builder, "% % % %\n", scheduler.current_world, scheduler.closed, scheduler.task_count, scheduler.request_count);
	for 0..scheduler.task_count - 1 {
		task := scheduler.tasks[it];
		print(
			*builder,
			"% % % % % % % % % %\n",
			task.world,
			task.declaration,
			task.milestone,
			task.outcome,
			task.value,
			task.runs,
			task.cycle_group,
			task.blocked_by,
			task.dependency_count,
			task.dependencies
		);
	}

	for 0..scheduler.request_count - 1 {
		request := scheduler.requests[it];
		print(
			*builder,
			"% % % % % %\n",
			request.world,
			request.task,
			request.outcome,
			request.value,
			request.pending_on_return,
			request.notifications
		);
	}

	return builder_to_string(*builder);
}

save_trace :: (
	scenario: Scenario,
	scheduler: *Scheduler,
	summary: *String_Builder,
	tasks: *String_Builder,
	requests: *String_Builder,
	dependencies: *String_Builder,
	audit: *Audit
) {
	computations: s64;
	cycles: s64;
	notifications: s64;
	for 0..scheduler.task_count - 1 {
		task := scheduler.tasks[it];
		computations += task.runs;
		cycles += (task.outcome == .CYCLE).(s64);
		print(
			tasks,
			"%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\t%\n",
			scenario,
			scheduler.reverse,
			it,
			task.world,
			task.declaration,
			task.milestone,
			task.outcome,
			task.value,
			task.runs,
			task.published_at,
			task.cycle_group,
			task.blocked_by
		);

		parent := it;
		for 0..task.dependency_count - 1 {
			print(dependencies, "%\t%\t%\t%\n", scenario, scheduler.reverse, parent, task.dependencies[it]);
			audit.dependency_records += 1;
		}
	}

	for 0..scheduler.request_count - 1 {
		request := scheduler.requests[it];
		notifications += request.notifications;
		print(
			requests,
			"%\t%\t%\t%\t%\t%\t%\t%\t%\n",
			scenario,
			scheduler.reverse,
			it,
			request.world,
			request.task,
			request.outcome,
			request.value,
			request.pending_on_return,
			request.notifications
		);
	}

	print(
		summary,
		"%\t%\t%\t%\t%\t%\t%\t%\n",
		scenario,
		scheduler.reverse,
		scheduler.checks,
		scheduler.task_count,
		scheduler.request_count,
		computations,
		notifications,
		cycles
	);

	audit.order_runs += 1;
	audit.expectation_checks += scheduler.checks;
	audit.task_records += scheduler.task_count;
	audit.request_records += scheduler.request_count;
}

run_negative_control :: (policy: Policy, controls: *String_Builder, audit: *Audit) {
	scheduler := Scheduler.{policy = policy};
	fixture := make_fixture(*scheduler);
	waiter := request_task(*scheduler, 1, 1, .BODY);
	other: s64 = -1;

	if policy == {
		case .NO_CYCLES; #through;
		case .POINTER_NEEDS_LAYOUT;
			depends_on(*scheduler, fixture.layout, fixture.layout);

		case .WORLD_BLIND;
			add_task(*scheduler, 2, 1, .SIGNATURE, 12);
			other = request_task(*scheduler, 2, 1, .SIGNATURE);

		case .CANCEL_SHARED;
			other = request_task(*scheduler, 1, 1, .BODY);
	}

	drain(*scheduler);
	expected: Outcome;
	observed: Outcome;
	expected_measure: s64;
	observed_measure: s64;

	if policy == {
		case .STALL_IS_CYCLE;
			expected = .PENDING;
			observed = scheduler.tasks[fixture.external].outcome;

		case .CANCEL_SHARED;
			assert(cancel_request(*scheduler, waiter));
			expected = .PENDING;
			observed = scheduler.requests[other].outcome;

		case .WORLD_BLIND;
			expected = .AVAILABLE;
			observed = scheduler.requests[other].outcome;
			expected_measure = 12;
			observed_measure = scheduler.requests[other].value;

		case .DECLARATION_BARRIER;
			expected = .AVAILABLE;
			observed = scheduler.tasks[fixture.signature].outcome;

		case .DOUBLE_NOTIFY;
			finish_external(*scheduler, fixture.external);
			drain(*scheduler);
			expected = .AVAILABLE;
			observed = scheduler.requests[waiter].outcome;
			expected_measure = 1;
			observed_measure = scheduler.requests[waiter].notifications;

		case .ACCEPT_LATE;
			shutdown(*scheduler);
			assert(complete_external(*scheduler, fixture.external, scheduler.tasks[fixture.external].token, .AVAILABLE, 50));
			expected = .SHUTDOWN;
			observed = scheduler.tasks[fixture.external].outcome;

		case .NO_CYCLES;
			expected = .CYCLE;
			observed = scheduler.tasks[fixture.layout].outcome;

		case .POINTER_NEEDS_LAYOUT;
			expected = .AVAILABLE;
			observed = scheduler.tasks[fixture.layout].outcome;

		case;
			assert(false);
	}

	assert(observed != expected || observed_measure != expected_measure, "E8 negative control was not detected: %", policy);
	print(controls, "%\t%\t%\t%\t%\n", policy, expected, expected_measure, observed, observed_measure);
	audit.negative_controls += 1;
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
	tasks: String_Builder;
	requests: String_Builder;
	dependencies: String_Builder;
	controls: String_Builder;
	defer reset(*summary);
	defer reset(*tasks);
	defer reset(*requests);
	defer reset(*dependencies);
	defer reset(*controls);

	print(*summary, "case\treverse\tchecks\ttasks\trequests\tcomputations\tnotifications\tcycles\n");
	print(*tasks, "case\treverse\ttask\tworld\tdeclaration\tmilestone\toutcome\tvalue\truns\tpublished_at\tcycle_group\tblocked_by\n");
	print(*requests, "case\treverse\trequest\tworld\ttask\toutcome\tvalue\tpending\tnotifications\n");
	print(*dependencies, "case\treverse\tparent\ttarget\n");
	print(*controls, "policy\texpected_outcome\texpected_measure\tobserved_outcome\tobserved_measure\n");
	audit: Audit;
	for scenario: enum_values_as_enum(Scenario) {
		forward := run_scenario(scenario, false);
		reverse := run_scenario(scenario, true);
		forward_result := completion_snapshot(*forward);
		reverse_result := completion_snapshot(*reverse);
		defer free(forward_result);
		defer free(reverse_result);

		assert(forward_result == reverse_result, "E8 order-dependent completion: %", scenario);
		audit.order_checks += 1;
		audit.scenarios += 1;
		save_trace(scenario, *forward, *summary, *tasks, *requests, *dependencies, *audit);
		save_trace(scenario, *reverse, *summary, *tasks, *requests, *dependencies, *audit);
		print("E8 %: both orders passed with % expectation checks.\n", scenario, forward.checks + reverse.checks);
	}

	for policy: enum_values_as_enum(Policy) {
		if policy != .CORRECT {
			run_negative_control(policy, *controls, *audit);
		}
	}

	assert(audit.scenarios == #run enum_names(Scenario).count);
	assert(audit.negative_controls == (#run enum_names(Policy).count) - 1);
	write_output("summary.tsv", *summary);
	write_output("tasks.tsv", *tasks);
	write_output("requests.tsv", *requests);
	write_output("dependencies.tsv", *dependencies);
	write_output("negative_controls.tsv", *controls);
	assert(write_entire_file(tprint("%/compiler_version.txt", OUTPUT_DIRECTORY), COMPILER_VERSION));

	audit_json := tprint(
		"{\"scenarios\":%,\"order_runs\":%,\"expectation_checks\":%,\"order_checks\":%,\"task_records\":%,\"request_records\":%,\"dependency_records\":%,\"negative_controls\":%}\n",
		audit.scenarios,
		audit.order_runs,
		audit.expectation_checks,
		audit.order_checks,
		audit.task_records,
		audit.request_records,
		audit.dependency_records,
		audit.negative_controls
	);

	assert(write_entire_file(tprint("%/audit_summary.json", OUTPUT_DIRECTORY), audit_json));
	print("E8 complete: % scenarios, % order runs, % expectation checks, % negative controls.\n", audit.scenarios, audit.order_runs, audit.expectation_checks, audit.negative_controls);
}
