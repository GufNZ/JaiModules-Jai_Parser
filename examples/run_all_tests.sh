#!/usr/bin/env bash
set -uo pipefail

usage() {
	printf '\e[97m%s\e[0m\n'															\
		'Usage: bash run_all_tests.sh [all|x64|llvm] [--dry-run]'						\
		'Run standalone tests and corpus checks with unfiltered compiler/test output.'	\
		'Default: x64 and optimized LLVM, plus native-worker traces on each backend.'	\
		'Differential fixtures run once through the bounded differential runner.'		\
		'Its child compile/runtime logs are printed after it finishes.'					\
		'Requires jai on PATH, or JAI=/path/to/jai.exe. Failures do not stop later tests.'
}

backend=all
dry_run=false
for argument in "$@"; do
	case "$argument" in
		all|x64|llvm) backend=$argument ;;
		--dry-run) dry_run=true ;;
		-h|--help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) || exit 1
cd -- "$script_dir" || exit 1
compiler=${JAI:-jai}
if [[ $dry_run == false ]] && ! command -v "$compiler" >/dev/null 2>&1; then
	printf '\e[91mCompiler not found: %s\e[0m\n' "$compiler" >&2
	exit 127
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
backends=(x64 llvm)
if [[ $backend != all ]]; then
	backends=("$backend")
fi

failures=()
configurations=0
declare -A build_status=()

run_test() {
	local target=$1 selected_backend=$2 variant=${3:-default}
	local label="$target ($selected_backend, $variant)" status build_key
	local -a build=("$compiler" "$target.jai")
	local -a run=("./$target$executable_suffix")
	if [[ $selected_backend == x64 ]]; then
		build+=(-x64)
	else
		build+=(-o -llvm)
	fi

	case "$variant" in
		real-worker) build+=(- real-worker) ;;
		self-test) run+=(--self-test) ;;
		all-fixtures) run+=(--all) ;;
	esac

	configurations=$((configurations + 1))
	printf '\n\e[96m=== %s ===\e[0m\n' "$label"
	printf -v build_key '%q ' "${build[@]}"
	if [[ ! ${build_status[$build_key]+present} ]]; then
		printf '%s\n' "$build_key"
		status=0
		if [[ $dry_run == false ]]; then
			if "${build[@]}"; then
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


	printf '%q ' "${run[@]}"
	printf '\n'
	if [[ $dry_run == false ]]; then
		if "${run[@]}"; then
			:
		else
			status=$?
			failures+=("$label: execution exited $status")
		fi
	fi
}

for selected_backend in "${backends[@]}"; do
	for target in "${tests[@]}"; do
		run_test "$target" "$selected_backend"
	done

	run_test service_traces_test "$selected_backend" real-worker
done

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

if [[ $dry_run == true ]]; then
	printf '\n\e[93mDry run: %s configurations planned; nothing compiled or executed.\e[0m\n' "$configurations"
elif (( ${#failures[@]} )); then
	printf '\n\e[91m%s failure(s) across %s configurations:\e[0m\n' "${#failures[@]}" "$configurations" >&2
	printf '  %s\n' "${failures[@]}" >&2
	exit 1
else
	printf '\n\e[92mAll %s configurations passed.\e[0m\n' "$configurations"
fi
