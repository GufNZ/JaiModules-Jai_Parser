#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";

Parser :: #import "Jai_Parser"(ENABLE_TRIVIA=true);

main :: () {
	path := join(#filepath, "../../../how_to");
	how_to_path := path_to_string(reduce_path(parse_path(path)));

	filenames: [..]string;

	visit_jai_file :: (info: *File_Visit_Info, results: *[..]string) {
		if ends_with(info.short_name, ".jai") {
			array_add(results, copy_string(info.full_name));
		}
	}

	visit_files(how_to_path, true, *filenames, visit_jai_file);

	files_with_diagnostics: s64;
	total_diagnostics: s64;
	for filename: filenames {
		source, success := read_entire_file(filename);
		assert(success, "Unable to read '%'.", filename);

		parsed := Parser.parse_file(source, filename);
		root := parsed.root.(*Parser.Parser_Block);
		assert(root.block_type == .DATA_DECLARATIONS);
		assert(Parser.reconstruct_source(*parsed) == source);
		assert(parsed.status != .FATAL);

		if parsed.status != .COMPLETE {
			files_with_diagnostics += 1;
			total_diagnostics += parsed.diagnostics.count;
			print("%: status %, % diagnostics; first: %\n", filename, parsed.status, parsed.diagnostics.count, parsed.diagnostics[0].message);
		}

		Parser.release_parser_tree(*parsed);
		free(source);
	}

	print("Parsed % how_to files; % files produced % diagnostics.\n", filenames.count, files_with_diagnostics, total_diagnostics);
}
