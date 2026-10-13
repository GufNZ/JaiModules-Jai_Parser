#!/usr/bin/env bash
set -euo pipefail

usage() {
	printf '\033[96mUsage\033[0m: clean_build_artifacts.sh [\033[93m--dry-run\033[0m] [\033[93m--resolved FIXTURE ...\033[0m]\n'
	printf '%s\n' \
		'Clean untracked build outputs in the parser examples directory.' \
		'Preserve retained differential fixtures and their outputs unless marked resolved.'
	printf '\033[93mFIXTURE\033[0m is a \033[96mjai_parser_differential_<section>_<test>_<serial>[.jai]\033[0m name.\n'
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
				printf '\033[91mInvalid resolved fixture name\033[0m: \033[96m%s\033[0m\n' "$2" >&2
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
			printf '\033[91mUnknown argument\033[0m: \033[93m%s\033[0m\n' "$1" >&2
			usage >&2
			exit 2
			;;
	esac
done

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

git rev-parse --is-inside-work-tree >/dev/null

declare -A tracked=()
exec {tracked_fd}< <(git ls-files -z -- .)
tracked_pid=$!
while IFS= read -r -d '' path; do
	tracked["$path"]=true
done <&"$tracked_fd"
exec {tracked_fd}<&-
wait "$tracked_pid"

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

pending=()
pending_length=0
remove_pending() {
	if (( ${#pending[@]} == 0 )); then
		return 0
	fi


	rm -- "${pending[@]}"
	local entry
	for entry in "${pending[@]}"; do
		printf '\033[92mRemoved\033[0m: \033[96m%s\033[0m\n' "${entry#./}"
	done

	pending=()
	pending_length=0
}

count=0
while IFS= read -r -d '' entry; do
	path=${entry#./}
	if [[ ${tracked["$path"]+present} ]]; then
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
		printf '\033[93mWould remove\033[0m: \033[96m%s\033[0m\n' "$path"
	else
		if (( ${#pending[@]} > 0 && (${#pending[@]} >= 128 || pending_length + ${#entry} + 1 > 8192) )); then
			remove_pending
		fi

		pending+=("$entry")
		pending_length=$((pending_length + ${#entry} + 1))
	fi

	count=$((count + 1))
done < <(find . -type d -name .git -prune -o -type f -print0)

if $dry_run; then
	printf '\033[93mWould remove\033[0m \033[97m%s\033[0m generated files.\n' "$count"
else
	remove_pending
	printf '\033[92mRemoved\033[0m \033[97m%s\033[0m generated files.\n' "$count"
fi
