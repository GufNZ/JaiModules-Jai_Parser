// Milestone-6 acceptance ledger: lists every acceptance case, records its verdict and tallies the results.
#import "Basic";

Verdict :: enum u8 {
	NOT_RUN;
	BLOCKED;
	PASS;
	FAIL;
	DEFERRED;
	EXCLUDED;
}

VERDICT_COUNT :: #run enum_names(Verdict).count;

Case_Scope :: enum u8 {
	INITIAL_FEATURE;
	INITIAL_REJECTION;
	DEFERRED_FEATURE;
	EXCLUDED_CLAIM;
}

Acceptance_Case :: struct {
	id: string;
	scope: Case_Scope;
	verdict: Verdict;
	note: string;
}

Case_Family :: struct {
	prefix: string;
	count: s64;
	scope: Case_Scope;
}

FAMILIES :: Case_Family.[
	.{prefix = "A", count = 15, scope = .INITIAL_FEATURE},
	.{prefix = "T", count = 8, scope = .INITIAL_FEATURE},
	.{prefix = "V", count = 8, scope = .INITIAL_FEATURE},
	.{prefix = "X", count = 8, scope = .INITIAL_FEATURE},
	.{prefix = "S", count = 8, scope = .INITIAL_FEATURE},
	.{prefix = "D", count = 8, scope = .DEFERRED_FEATURE},
];

build_ledger :: () -> [..] Acceptance_Case {
	cases: [..] Acceptance_Case;
	for family: FAMILIES {
		for 1..family.count {
			verdict: Verdict = ifx family.scope == .DEFERRED_FEATURE
				then .DEFERRED
				else .NOT_RUN;

			array_add(
				*cases,
				.{
					id = sprint("%1%2", family.prefix, it),
					scope = family.scope,
					verdict = verdict
				}
			);
		}
	}

	return cases;
}

tally_ledger :: (cases: [] Acceptance_Case) -> [VERDICT_COUNT] s64 {
	tally: [VERDICT_COUNT] s64;
	for cases {
		tally[it.verdict] += 1;
	}

	return tally;
}

ledger_failed :: (tally: [VERDICT_COUNT] s64) -> bool {
	return tally[Verdict.FAIL] || tally[Verdict.BLOCKED];
}

self_test :: () {
	cases := build_ledger();
	defer array_free(cases);

	assert(!ledger_failed(tally_ledger(cases)));
	cases[0].verdict = .FAIL;
	assert(ledger_failed(tally_ledger(cases)));
	cases[0].verdict = .BLOCKED;
	assert(ledger_failed(tally_ledger(cases)));
	cases[0].verdict = .PASS;
	assert(!ledger_failed(tally_ledger(cases)));
	print("Self-test PASS.\n");
}

main :: () {
	arguments := get_command_line_arguments();
	if arguments.count > 1 && arguments[1] == "--self-test" {
		self_test();
		return;
	}


	cases := build_ledger();
	tally := tally_ledger(cases);
	for cases {
		if it.verdict == .FAIL || it.verdict == .BLOCKED {
			print("% %: %\n", it.id, it.verdict, it.note);
		}
	}

	print("Acceptance cases: %\n", cases.count);
	for tally {
		print("  %: %\n", it_index.(Verdict), it);
	}

	if ledger_failed(tally) {
		exit(1);
	}
}
