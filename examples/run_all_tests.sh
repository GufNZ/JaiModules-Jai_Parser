#!/usr/bin/env bash
set -uo pipefail

usage() {
	printf '\e[97m%s\e[0m\n'																					\
		'Usage: bash run_all_tests.sh [all|x64|llvm] [OPTIONS]'													\
		'Run standalone tests and corpus checks with unfiltered compiler/test output.'							\
		'Default: x64 and optimized LLVM, plus native-worker traces on each backend.'							\
		'--service: only worker/provider/coordinator/host/default and real-worker traces.'						\
		'--analysis-ticket or --batch-pool: only the focused worker configuration.'								\
		'--repeat=N: run each compiled configuration N times (1..30; default 1).'								\
		'--timeout=N: execution timeout in seconds (0 disables; default 240 for service modes, otherwise 0).'	\
		'--summary: show pass/error summaries and retain full logs under .build/test_runs.'						\
		'--expect-summaries=N: require exactly N analysis summaries with --analysis-ticket.'					\
		'--dry-run: print configurations without compiling or executing.'										\
		'--check: check runner syntax, Git whitespace and worker line width without compiling.'					\
		'Differential fixtures run once through the bounded differential runner.'								\
		'Its child compile/runtime logs are printed after it finishes.'											\
		'Requires jai on PATH, or JAI=/path/to/jai.exe.  Failures do not stop later tests.'
	printf '%s\n' '--query-operation: only focused pending-query operation backing checks.'
}

backend=all
dry_run=false
checks_only=false
suite=all
repeat=1
timeout_seconds=auto
summary=false
expected_summaries=0
for argument in "$@"; do
	case "$argument" in
		all|x64|llvm) backend=$argument ;;
		--service) suite=service ;;
		--analysis-ticket) suite=analysis-ticket ;;
		--batch-pool) suite=batch-pool ;;
		--query-operation) suite=query-operation ;;
		--repeat=*) repeat=${argument#*=} ;;
		--timeout=*) timeout_seconds=${argument#*=} ;;
		--summary) summary=true ;;
		--expect-summaries=*) expected_summaries=${argument#*=} ;;
		--dry-run) dry_run=true ;;
		--check) checks_only=true ;;
		-?|-h|--help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done

if [[ ! $repeat =~ ^([1-9]|[12][0-9]|30)$ ]]; then
	printf '\e[91m%s\e[0m\n' '--repeat must be an integer from 1 to 30.' >&2
	exit 2
fi

if [[ $timeout_seconds == auto ]]; then
	timeout_seconds=0
	if [[ $suite != all ]]; then
		timeout_seconds=240
	fi
fi

if [[ ! $timeout_seconds =~ ^(0|[1-9][0-9]{0,4})$ ]] || (( timeout_seconds > 86400 )); then
	printf '\e[91m%s\e[0m\n' '--timeout must be an integer from 0 to 86400.' >&2
	exit 2
fi

if [[ ! $expected_summaries =~ ^(0|[1-9][0-9]{0,5})$ ]] || [[ $expected_summaries != 0 && $suite != analysis-ticket ]]; then
	printf '\e[91m%s\e[0m\n' '--expect-summaries requires --analysis-ticket and an integer from 0 to 999999.' >&2
	exit 2
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) || exit 1
cd -- "$script_dir" || exit 1
if [[ $checks_only == true ]]; then
	if [[ $dry_run == true ]]; then
		printf '%s\n' 'Dry run: runner syntax, Git whitespace and worker line-width checks; nothing executed.'
		exit 0
	fi

	status=0
	if ! bash -n "$script_dir/run_all_tests.sh"; then
		status=1
	fi
	if ! git -C .. diff --check; then
		status=1
	fi
	if ! awk '
		length($0) > 175 { print FILENAME ":" FNR ":" length($0) ":" $0; count++ }
		END { print "Worker lines over 175 characters:", count + 0; if (count) { exit 1 } }
	' service_worker_test.jai; then
		status=1
	fi
	if (( status == 0 )); then
		printf 'Static checks \e[32mPASS\e[0m\n'
	fi
	exit "$status"
fi

compiler=${JAI:-jai}
if [[ $dry_run == false ]] && ! command -v "$compiler" >/dev/null 2>&1; then
	printf '\e[91mCompiler not found: %s\e[0m\n' "$compiler" >&2
	exit 127
fi

if [[ $dry_run == false && $timeout_seconds != 0 ]] && ! command -v timeout >/dev/null 2>&1; then
	printf '\e[91m%s\e[0m\n' 'timeout was not found; install GNU coreutils or use --timeout=0.' >&2
	exit 127
fi

log_dir=
if [[ $dry_run == false && $summary == true ]]; then
	mkdir -p .build/test_runs || exit 1
	log_dir=$(mktemp -d .build/test_runs/run.XXXXXX) || exit 1
fi

trap 'exit 130' INT
trap 'exit 143' TERM
case "$(uname -s)" in
	CYGWIN*|MINGW*|MSYS*) executable_suffix=.exe ;;
	*) executable_suffix= ;;
esac

tests=(
	layout_test
	parser_tokens_test
	lex_all_files
	parse_how_to
	service_foundations_test
	service_context_test
	service_provider_test
	service_snapshot_test
	service_coordinator_test
	service_host_test
	service_worker_test
	service_traces_test
)
case "$suite" in
	service) tests=(service_worker_test service_provider_test service_coordinator_test service_host_test service_traces_test) ;;
	analysis-ticket|batch-pool|query-operation) tests=(service_worker_test) ;;
esac

backends=(x64 llvm)
if [[ $backend != all ]]; then
	backends=("$backend")
fi

failures=()
configurations=0
declare -A build_status=()

execute_command() {
	local log=$1 require_pass=$2 expected=$3
	local destination=/dev/null
	shift 3
	if [[ $log_dir ]]; then
		destination=$log
	fi
	if [[ $summary == true || $expected != 0 || $require_pass == true ]]; then
		"$@" 2>&1 | tee "$destination" | awk -v require_pass="$require_pass" -v expected="$expected" -v concise="$summary" '
			{
				line = $0;
				if (line ~ /^Service.*PASS/) { passed = 1 }
				if (line ~ /^X5 analysis candidate|^X5 analysis ticket|^X5 analysis receipt|^X3\/X5 analysis receipt|^Service analysis/) { count++ }
				problem = line ~ /Error:|Assertion|assertion|Wrong number|\.jai:|Cleanup callback|Held heap-gate/;
				if (require_pass == "true" && problem) { failed = 1 }
				if (concise != "true" || problem || line ~ /^Service.*PASS|Warning:|FAIL/) { print line }
			}
			END {
				if (concise == "true" && count) { print "Analysis summaries:", count }
				if (expected && count != expected) { print "Expected analysis summaries:", expected, "observed:", count + 0; failed = 1 }
				if (require_pass == "true" && !passed) { print "Missing service PASS summary."; failed = 1 }
				if (failed) { exit 1 }
			}'
		local -a command_status=("${PIPESTATUS[@]}")
		if (( command_status[0] )); then
			printf 'Command exited with native status %s.\n' "${command_status[0]}" >&2
			return "${command_status[0]}"
		fi
		if (( command_status[1] )); then
			return "${command_status[1]}"
		fi
		return "${command_status[2]}"
	else
		"$@"
	fi
}

run_test() {
	local target=$1 selected_backend=$2 variant=${3:-default}
	local label="$target ($selected_backend, $variant)" status build_key attempt require_pass=false expected=0
	local log_prefix="${log_dir:+$log_dir/}$target.$selected_backend.$variant"
	local -a build=("$compiler" "$target.jai")
	local -a run=("./$target$executable_suffix")
	if [[ $selected_backend == x64 ]]; then
		build+=(-x64)
	else
		build+=(-o -llvm)
	fi

	case "$variant" in
		real-worker|analysis-ticket|batch-pool|query-operation) build+=(- "$variant") ;;
		self-test) run+=(--self-test) ;;
		all-fixtures) run+=(--all) ;;
	esac

	if [[ $timeout_seconds != 0 ]]; then
		run=(timeout "$timeout_seconds" "${run[@]}")
	fi
	if [[ $target == service_* ]]; then
		require_pass=true
	fi
	if [[ $variant == analysis-ticket ]]; then
		expected=$expected_summaries
	fi

	configurations=$((configurations + 1))
	printf '\n\e[96m=== %s ===\e[0m\n' "$label"
	printf -v build_key '%q ' "${build[@]}"
	if [[ ! ${build_status[$build_key]+present} ]]; then
		printf '%s\n' "$build_key"
		status=0
		if [[ $dry_run == false ]]; then
			if execute_command "$log_prefix.compile.log" false 0 "${build[@]}"; then
				:
			else
				status=$?
			fi
		fi

		build_status["$build_key"]=$status
	fi

	status=${build_status[$build_key]}
	if (( status )); then
		failures+=("$label: compilation exited $status")
		return
	fi


	for (( attempt=1; attempt<=repeat; attempt++ )); do
		printf '\e[95mRun \e[94m%s\e[95m/\e[94m%s: \e[33m' "$attempt" "$repeat"
		printf '%q ' "${run[@]}"
		printf '\e[0m\n'
		if [[ $dry_run == false ]]; then
			if execute_command "$log_prefix.run-$attempt.log" "$require_pass" "$expected" "${run[@]}"; then
				:
			else
				status=$?
				failures+=("$label, run $attempt/$repeat: execution exited $status")
			fi
		fi
	done
}

run_selected_tests() {
	for selected_backend in "${backends[@]}"; do
		for target in "${tests[@]}"; do
			if [[ $suite == analysis-ticket || $suite == batch-pool || $suite == query-operation ]]; then
				run_test "$target" "$selected_backend" "$suite"
			else
				run_test "$target" "$selected_backend"
			fi
		done

		if [[ $suite == all || $suite == service ]]; then
			run_test service_traces_test "$selected_backend" real-worker
		fi
	done

	if [[ $suite == all ]]; then
		declare -A previous_runs=()
		for directory in .build/differential_runs/*; do
			if [[ -d $directory ]]; then
				previous_runs["$directory"]=1
			fi
		done

		run_test differential_runner "${backends[0]}" self-test
		run_test differential_runner "${backends[0]}" all-fixtures
		if [[ $dry_run == false ]]; then
			for directory in .build/differential_runs/*; do
				if [[ ! -d $directory || ${previous_runs["$directory"]+present} ]]; then
					continue
				fi


				while IFS= read -r -d '' log; do
					printf '\n\e[96m=== Differential child output: %s ===\e[0m\n' "$log"
					if ! cat -- "$log"; then
						failures+=("Could not read $log")
					fi
				done < <(find "$directory" -type f \( -name compile.log -o -name runtime.log \) -print0 | sort -z)
			done
		fi
	fi

	if [[ $log_dir ]]; then
		printf '\nFull logs: %s/%s\n' "$script_dir" "$log_dir"
	fi

	if [[ $dry_run == true ]]; then
		printf '\n\e[93mDry run: %s configurations, %s execution(s) each; nothing compiled or executed.\e[0m\n' "$configurations" "$repeat"
	elif (( ${#failures[@]} )); then
		printf '\n\e[91m%s failure(s) across %s configurations:\e[0m\n' "${#failures[@]}" "$configurations" >&2
		printf '  %s\n' "${failures[@]}" >&2
		exit 1
	else
		printf '\n\e[92mAll %s configurations passed (%s execution(s) each).\e[0m\n' "$configurations" "$repeat"
	fi
	exit 0
}

run_selected_tests
