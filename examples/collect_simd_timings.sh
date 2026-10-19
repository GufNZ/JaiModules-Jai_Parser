#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
	printf '%s\n' \
		'Usage: bash collect_simd_timings.sh [--workloads] [--rounds N] [--output-dir DIRECTORY] [--] [CORPUS ...]' \
		'Collect scalar versus automatic widest-SIMD timings on Windows Bash.' \
		'--workloads adds five deterministic workloads with streaming/materialised and fresh/reused pool phases.' \
		'Defaults: three rounds; Invaders and how_to from the Jai distribution.' \
		'Requires jai on PATH (or JAI=/path/to/jai.exe).  N must be 1..30.' \
		'Each round performs token parity, two warmups, and nine trials of 25 scans.' \
		'Output: a timestamped directory under examples/.build, or --output-dir.'
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
compiler=${JAI:-jai}
rounds=3
include_workloads=false
output_root="$script_dir/.build"
corpora=()
while (( $# )); do
	case "$1" in
		-h|--help)
			usage
			exit 0
			;;

		--workloads)
			include_workloads=true
			shift
			;;

		--rounds|--output-dir)
			if (( $# < 2 )); then
				usage >&2
				exit 2
			fi


			if [[ $1 == --rounds ]]; then
				rounds=$2
			else
				output_root=$2
			fi

			shift 2
			;;

		--)
			shift
			corpora+=("$@")
			break
			;;

		-*)
			printf 'Unknown option: %s\n' "$1" >&2
			usage >&2
			exit 2
			;;

		*)
			corpora+=("$1")
			shift
			;;
	esac
done

if [[ ! $rounds =~ ^[1-9][0-9]?$ ]] || (( rounds > 30 )); then
	printf '%s\n' '--rounds must be an integer from 1 to 30.' >&2
	exit 2
fi

case "$(uname -s)" in
	CYGWIN*|MINGW*|MSYS*) ;;
	*)
		printf '%s\n' 'This collector script currently supports Windows only.  Run it in Cygwin, MSYS, or Git Bash.' >&2
		exit 2
		;;
esac

if ! command -v "$compiler" >/dev/null; then
	printf 'Jai compiler not found: %s.  Set JAI or add jai to PATH.\n' "$compiler" >&2
	exit 2
fi


compiler=$(command -v "$compiler")
if [[ $compiler == */* ]]; then
	compiler="$(cd -- "$(dirname -- "$compiler")" && pwd -P)/$(basename -- "$compiler")"
fi

native_path() {
	if command -v cygpath >/dev/null; then
		cygpath -m "$1"
	else
		printf '%s\n' "$1"
	fi
}

if (( ${#corpora[@]} == 0 )); then
	corpora=("$script_dir/../../../examples/invaders" "$script_dir/../../../how_to")
fi

for index in "${!corpora[@]}"; do
	if [[ ! -d ${corpora[index]} ]]; then
		printf 'Corpus directory not found: %s.  Supply one or more CORPUS directories.\n' "${corpora[index]}" >&2
		exit 2
	fi


	corpora[index]=$(native_path "$(cd -- "${corpora[index]}" && pwd -P)")
done

mkdir -p -- "$output_root"
output_root=$(cd -- "$output_root" && pwd -P)
run_dir="$output_root/simd_timings_$(date -u +%Y%m%dT%H%M%SZ)_$$"
mkdir -- "$run_dir"
report="$run_dir/report.txt"
compiler_output=$(native_path "$run_dir")
cd -- "$script_dir"
export LC_ALL=C

trap 'status=$?; printf "\nFAILED (exit %s). Partial report: %s\n" "$status" "$report" | tee -a "$report"; exit "$status"' ERR

run_logged() {
	{
		printf '\n=== %s ===\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
		printf 'Command: '
		printf '%q ' "$@"
		printf '\n'
	} | tee -a "$report"
	"$@" 2>&1 | tee -a "$report"
}

{
	printf 'Jai SIMD Timing Collection\nUTC: %s\nRounds: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$rounds"
	printf 'Report: %s\nCompiler: %s\nBash: %s\n' "$report" "$compiler" "$BASH_VERSION"
	printf '\n=== Host ===\n'
	uname -a
	printf 'PROCESSOR_IDENTIFIER: %s\n' "${PROCESSOR_IDENTIFIER:-unavailable}"
	if [[ -r /proc/cpuinfo ]]; then
		while IFS= read -r line; do
			if [[ -z $line ]]; then
				break
			fi


			printf '%s\n' "$line"
		done < /proc/cpuinfo
	fi
	printf '\n=== Source Provenance ===\n'
	if command -v git >/dev/null; then
		git rev-parse HEAD || true
		git status --short -- ../module.jai ../lexer.jai layout_test.jai lex_all_files.jai collect_simd_timings.sh || true
	fi

	if command -v sha256sum >/dev/null; then
		sha256sum ../module.jai ../lexer.jai layout_test.jai lex_all_files.jai collect_simd_timings.sh
	fi

	printf '\n=== Corpora ===\n'
	printf '%s\n' "${corpora[@]}"
	printf '\nTimings exclude I/O, compiler startup, and AST parsing; include token allocation/cleanup.\n'
	printf 'USE_SIMD selects the widest CPU/OS-supported path; the benchmark reports the selected path.\n'
	printf 'Scalar and SIMD trial order alternates within each round.\n'
	printf 'Synthetic workloads enabled: %s. Allocation counters run outside timing.\n' "$include_workloads"
	printf 'Keep machine power settings consistent and avoid other CPU-heavy work.\n'
} 2>&1 | tee "$report"

run_logged "$compiler" layout_test.jai -version -x64 -quiet -no_color -output_path "$compiler_output" -exe layout_fast
run_logged "$run_dir/layout_fast.exe"
run_logged "$compiler" layout_test.jai -o -llvm -quiet -no_color -output_path "$compiler_output" -exe layout_llvm
run_logged "$run_dir/layout_llvm.exe"
run_logged "$compiler" lex_all_files.jai -o -llvm -quiet -no_color -output_path "$compiler_output" -exe lex_benchmark

for (( round=0; round<rounds; round++ )); do
	printf '\n=== Round %s/%s: automatic SIMD ===\n' "$((round + 1))" "$rounds" | tee -a "$report"
	run_logged "$run_dir/lex_benchmark.exe" --benchmark "${corpora[@]}"
	if [[ $include_workloads == true ]]; then
		run_logged "$run_dir/lex_benchmark.exe" --benchmark-workloads
	fi
done

printf '\nCollection COMPLETE. Report: %s\n' "$report" | tee -a "$report"
