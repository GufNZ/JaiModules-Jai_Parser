#!/usr/bin/env bash
set -uo pipefail

compiler=${JAI:-jai}
if ! command -v "$compiler" >/dev/null 2>&1; then
	printf 'Compiler not found: %s\n' "$compiler" >&2
	exit 2
fi

cd -- "$(dirname -- "${BASH_SOURCE[0]}")" || exit 2
mkdir -p .build || exit 2
probe_dir=$(mktemp -d .build/integer-boundaries.XXXXXX) || exit 2
printf 'Probe artifacts: %s/%s\n' "$PWD" "$probe_dir"
cd -- "$probe_dir" || exit 2
"$compiler" -version || exit 2

case "$(uname -s)" in
	CYGWIN*|MINGW*|MSYS*) suffix=.exe ;;
	*) suffix= ;;
esac

total=0
mismatches=0
errors=0
printf 'type\tboundary\tvalue\tform\texpected\tobserved\tverdict\n' > results.tsv

probe() {
	local target=$1 boundary=$2 value=$3 expected=$4 form=$5
	local stem=${target}_${boundary}_${form} argument=$value observed verdict diagnostic
	{
		printf '#import "Basic";\n\n'
		if [[ $form != assignment ]]; then
			printf 'take :: (value: %s) { print("%%\\n", value); }\n' "$target"
			if [[ $form == overload_* ]]; then
				printf 'take :: (value: string) { print("unexpected string: %%\\n", value); }\n'
			fi
		fi
		printf '\nmain :: () {\n'
		if [[ $form == *_named ]]; then
			printf '\tconstant :: %s;\n' "$value"
			argument=constant
		fi
		if [[ $form == assignment ]]; then
			printf '\tvalue: %s = %s;\n\tprint("%%\\n", value);\n' "$target" "$argument"
		else
			printf '\ttake(%s);\n' "$argument"
		fi
		printf '}\n'
	} > "$stem.jai" || return 2

	total=$((total + 1))
	if "$compiler" -x64 "$stem.jai" > "$stem.compile.log" 2>&1; then
		if observed=$("./$stem$suffix" 2> "$stem.runtime.log"); then
			observed=${observed//$'\r'/}
		else
			observed=runtime-error
		fi
	else
		diagnostic=$(<"$stem.compile.log")
		observed=compile-error
		if [[ $diagnostic == *'Error:'* && $diagnostic == *"$stem.jai:"* ]]; then
			observed=rejected
		fi
	fi

	if [[ $observed == compile-error || $observed == runtime-error ]]; then
		verdict=error
		errors=$((errors + 1))
	elif [[ $observed == "$expected" ]]; then
		verdict=match
	else
		verdict=mismatch
		mismatches=$((mismatches + 1))
	fi
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$target" "$boundary" "$value" "$form" "$expected" "$observed" "$verdict" >> results.tsv
	if [[ $verdict != match ]]; then
		printf '%s %s (%s), %s: expected %s, observed %s\n' "$target" "$boundary" "$value" "$form" "$expected" "$observed"
	fi
}

probe_boundary() {
	local target=$1 boundary=$2 value=$3 expected=$4 form
	if [[ $expected == in_range ]]; then
		expected=$value
	fi
	for form in assignment call_literal call_named overload_literal overload_named; do
		probe "$target" "$boundary" "$value" "$expected" "$form" || exit 2
	done
}

while read -r target below minimum next previous maximum above; do
	probe_boundary "$target" below_min "$below" rejected
	probe_boundary "$target" min "$minimum" in_range
	probe_boundary "$target" min_plus_one "$next" in_range
	probe_boundary "$target" max_minus_one "$previous" in_range
	probe_boundary "$target" max "$maximum" in_range
	probe_boundary "$target" above_max "$above" rejected
	if [[ $target == u* ]]; then
		probe_boundary "$target" signed_min -9223372036854775808 rejected
	fi
done <<'BOUNDARIES'
s8 -129 -128 -127 126 127 128
s16 -32769 -32768 -32767 32766 32767 32768
s32 -2147483649 -2147483648 -2147483647 2147483646 2147483647 2147483648
s64 -9223372036854775809 -9223372036854775808 -9223372036854775807 9223372036854775806 9223372036854775807 9223372036854775808
u8 -1 0 1 254 255 256
u16 -1 0 1 65534 65535 65536
u32 -1 0 1 4294967294 4294967295 4294967296
u64 -1 0 1 18446744073709551614 18446744073709551615 18446744073709551616
BOUNDARIES

printf '\n%s cases: %s matched range expectations, %s mismatches, %s probe errors.\n' "$total" "$((total - mismatches - errors))" "$mismatches" "$errors"
if (( errors )); then
	exit 2
fi
if (( mismatches )); then
	exit 1
fi