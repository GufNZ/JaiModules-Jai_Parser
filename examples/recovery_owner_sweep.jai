// Mutation sweep over the W2 inventories: deletes, duplicates or truncates at single tokens and reports recovery events whose recorded owner is not in the published tree (a parser discard site without `release_recoveries`).
// Run from this directory: jai recovery_owner_sweep.jai -x64 -quiet && ./recovery_owner_sweep.exe
#import "Basic";
#import "File";
#import "File_Utilities";
#import "Random";
#import "String";

Service :: #import "Jai_Parser/service";
Parser :: Service.Parser;

JAI_ROOT :: #run tprint("%../../..", #filepath);
MUTATION_POSITIONS :: 60;

Finding :: struct {
	key: string;
	count: s64;
	example: string;
}

findings: [..] Finding;
parses: s64;

check :: (source: string, label: string) {
	parses += 1;
	owned := Service.own_parse(source, label);
	defer Service.release_owned_syntax(owned);

	fault, snapshot := Service.project_snapshot(owned);
	assert(fault.failure == .NONE, "Snapshot of % failed: %.", label, fault.failure);
	defer Service.release_snapshot(snapshot);

	for snapshot.recoveries {
		if it.discarded || it.owner != .UNPUBLISHED {
			continue;
		}


		record := owned.parsed.recovery_records[it_index];
		first := record.owner.first_token.(s64);
		excerpt := slice(owned.source, owned.parsed.tokens[max(first - 3, 0)].byte_start, 80);
		key := tprint("% owned by an unpublished %", record.kind, record.owner.kind);
		found := false;
		for * findings {
			if it.key == key {
				it.count += 1;
				found = true;
			}
		}

		if !found {
			array_add(*findings, .{copy_string(key), 1, copy_string(tprint("%: ...%...", label, excerpt))});
		}
	}
}

visit :: (info: *File_Visit_Info, files: *[..] string) {
	if !info.is_directory && ends_with(info.full_name, ".jai") {
		array_add(files, copy_string(info.full_name));
	}
}

main :: () {
	files: [..] string;
	inventories := string.["how_to", "examples/invaders", "modules/Jai_Parser", "modules/Basic"];
	recursive := bool.[false, true, false, false];
	for inventories {
		visit_files(tprint("%/%", JAI_ROOT, it), recursive[it_index], *files, visit, visit_symlinks = false);
	}

	random_seed(12345);
	for path: files {
		source := read_entire_file(path);
		baseline := Parser.parse_file(source, path, resolve_identifiers = false);
		count := baseline.tokens.count - 1;
		if count < 1 {
			continue;
		}


		// Half the positions are evenly spread; the rest are seeded random.
		for step: 0..MUTATION_POSITIONS - 1 {
			index := ifx step < MUTATION_POSITIONS / 2
				then (step * count) / (MUTATION_POSITIONS / 2)
				else (random_get() % count.(u64)).(s64);

			start := baseline.tokens[index].byte_start;
			end := baseline.tokens[index].byte_end;
			check(join(slice(source, 0, start), slice(source, end, source.count - end)), tprint("% delete %", path, index));
			check(join(slice(source, 0, end), slice(source, start, source.count - start)), tprint("% duplicate %", path, index));
			if step % 3 == 0 {
				check(slice(source, 0, end), tprint("% truncate %", path, index));
			}

			reset_temporary_storage();
		}
	}

	print("% mutated parses, % findings.\n", parses, findings.count);
	for findings {
		print("% x%\n    %\n", it.key, it.count, it.example);
	}

	if findings.count {
		exit(1);
	}


	print("Recovery owner sweep PASS.\n");
}
