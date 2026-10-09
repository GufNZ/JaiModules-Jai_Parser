#!/usr/bin/env bash
set -euo pipefail

usage() {
	printf '%s\n' \
		'Usage: bash clean_build_artifacts.sh [--dry-run] [--resolved FIXTURE ...]' \
		'Clean untracked build outputs in the parser examples directory.' \
		'Preserve retained differential fixtures and their outputs unless marked resolved.' \
		'FIXTURE is a jai_parser_differential_<section>_<test>_<serial>[.jai] name.'
}

dry_run=false
resolved=()
while (( $# )); do
	case "$1" in
		--dry-run)
			dry_run=true
			shift
			;;

		--resolved)
			if (( $# < 2 )); then
				usage >&2
				exit 2
			fi

			stem=${2%.jai}
			if [[ ! $stem =~ ^jai_parser_differential_[0-9]+_[0-9]+_[0-9]+$ ]]; then
				printf 'Invalid resolved fixture name: %s\n' "$2" >&2
				exit 2
			fi

			resolved+=("$stem")
			shift 2

			;;
		'-?'|-h|--help)
			usage
			exit 0
			;;

		*)
			printf 'Unknown argument: %s\n' "$1" >&2
			usage >&2
			exit 2
			;;
	esac
done

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

git rev-parse --is-inside-work-tree >/dev/null

is_resolved() {
	local stem
	for stem in "${resolved[@]}"; do
		if [[ $1 == "$stem" ]]; then
			return 0
		fi
	done


	return 1
}

retained=()
while IFS= read -r -d '' source; do
	stem=${source#./}
	stem=${stem%.jai}
	if ! is_resolved "$stem"; then
		retained+=("$stem")
	fi
done < <(find . -maxdepth 1 -type f -name 'jai_parser_differential_*.jai' -print0)

is_retained_output() {
	local stem
	for stem in "${retained[@]}"; do
		if [[ $1 == "$stem" || $1 == "$stem"_* ]]; then
			return 0
		fi
	done


	return 1
}

count=0
while IFS= read -r -d '' entry; do
	path=${entry#./}
	if git ls-files --error-unmatch -- "$path" >/dev/null 2>&1; then
		continue
	fi


	filename=${path##*/}
	stem=${filename%.*}
	if is_retained_output "$stem"; then
		continue
	fi


	candidate=false
	case "$path" in
		.build/*|*/.build/*)
			candidate=true
			;;

		*)
			if [[ $path != */* ]]; then
				case "$filename" in
					*.exe|*.rdi|*.obj|*.lib|*.exp|*.pdb|*.ilk|*.o|*.a|*.dll|*.so|*.dylib)
						candidate=true
						;;

					*.jai|*.txt)
						if is_resolved "$stem"; then
							candidate=true
						fi
						;;
				esac
			fi
			;;
	esac

	if ! $candidate; then
		continue
	fi



	if $dry_run; then
		printf 'Would remove: %s\n' "$path"
	else
		rm -- "$entry"
		printf 'Removed: %s\n' "$path"
	fi

	count=$((count + 1))
done < <(find . -type d -name .git -prune -o -type f -print0)

if $dry_run; then
	printf 'Would remove %s generated files.\n' "$count"
else
	printf 'Removed %s generated files.\n' "$count"
fi
