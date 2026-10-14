#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
	printf '%s\n' \
		'Usage: bash collect_simd_timings.sh [--rounds N] [--output-dir DIRECTORY] [--] [CORPUS ...]' \
		'Collect scalar-relative SSE2, AVX2, and AVX-512 timings on Windows Bash.' \
		'Defaults: three rounds; Invaders and how_to from the Jai distribution.' \
		'Requires jai on PATH (or JAI=/path/to/jai.exe).  N must be 1..30.' \
		'Each mode performs token parity, two warmups, and nine trials of 25 scans.' \
		'Output: a timestamped directory under examples/.build, or --output-dir.'
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
compiler=${JAI:-jai}
rounds=3
output_root="$script_dir/.build"
corpora=()
while (( $# )); do
	case "$1" in
		-h|--help)
			usage
			exit 0
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
		printf '%s\n' 'The Jai timing benchmark currently requires Windows.  Run this script in Cygwin, MSYS, or Git Bash.' >&2
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
	printf 'Each mode compares against its own scalar baseline; compare relative speedups, not separate absolute times.\n'
	printf 'Mode order rotates each round.  Unsupported AVX-512 timings are fallback measurements.\n'
	printf 'Keep machine power settings consistent and avoid other CPU-heavy work.\n'
} 2>&1 | tee "$report"

run_logged "$compiler" layout_test.jai -version -x64 -quiet -no_color -output_path "$compiler_output" -exe layout_fast
run_logged "$run_dir/layout_fast.exe"
run_logged "$compiler" layout_test.jai -o -llvm -quiet -no_color -output_path "$compiler_output" -exe layout_llvm
run_logged "$run_dir/layout_llvm.exe"
run_logged "$compiler" lex_all_files.jai -o -llvm -quiet -no_color -output_path "$compiler_output" -exe lex_benchmark

modes=(SSE2 AVX2 AVX-512)
flags=(--benchmark --benchmark-avx2 --benchmark-avx512)
for (( round=0; round<rounds; round++ )); do
	for (( slot=0; slot<${#modes[@]}; slot++ )); do
		index=$(( (round + slot) % ${#modes[@]} ))
		printf '\n=== Round %s/%s: %s ===\n' "$((round + 1))" "$rounds" "${modes[index]}" | tee -a "$report"
		run_logged "$run_dir/lex_benchmark.exe" "${flags[index]}" "${corpora[@]}"
	done
done

printf '\nCollection COMPLETE. Report: %s\n' "$report" | tee -a "$report"
