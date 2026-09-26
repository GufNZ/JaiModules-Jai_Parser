# Jai_Parser

## Tests

Run these from `modules/Jai_Parser/examples` with `jai <file>.jai -x64 && ./<file>.exe`.

- `layout_test.jai` checks default lexer layout compatibility and focused token, trivia, here-string, and keyword behaviour across import options.
- `lex_all_files.jai` scans `.jai` files under `modules`, checking that lexer tokens and trivia account for every source byte without lexer errors.
- `parser_tokens_test.jai` checks parser-owned token spans and AST shapes, source round trips, and recovery on focused valid and invalid inputs.
- `differential_test.jai` compares parser ASTs and selected diagnostics with the Jai compiler, including contextual and typechecked fixtures.
- `parse_how_to.jai` parses the `how_to` corpus, checks nonfatal roots and exact source round trips, and reports zero-diagnostic files, first failing source lines, and diagnostic changes against its checked-in baseline.

## Lexer

This module starts from `Jai_Lexer` and adds current parser-oriented tokenisation.

The default import retains the original `Token` layout:

```jai
#import "Jai_Parser";
```

Lossless source text and trivia are opt-in:

```jai
#import "Jai_Parser"(ENABLE_TRIVIA=true);
```

In this mode, `Token` additionally contains:

- `original_text`: the exact source bytes forming the token.
- `preceding_trivia`: whitespace, comments, and ignored source bytes before the token.
- `trailing_trivia`: remaining trivia on the `END_OF_INPUT` token.

These strings are zero-copy slices of `Lexer.input`.
They remain valid only while that input remains installed in the lexer.
Calling `set_input_from_string` or `set_input_from_file` can invalidate slices from the previous input.
By default, standalone lexers copy identifier names.
A caller can optionally provide `Identifier_Storage` with `set_identifier_storage(*lexer, *storage)` to intern names without a shared table or lock.
The caller must keep the storage and borrowed source buffers supplying its names alive while those names are used.
Lexer-owned file input is copied into the supplied storage, so resetting that input does not invalidate names; it can still invalidate token trivia.  `release_identifier_storage(*storage)` frees the table and fallback pool after all names are no longer used.
Restoring a null storage uses the copying path again.

Structured trivia is available through a `for_expansion`:

```jai
for trivia, offset: make_trivia_iterator(token.preceding_trivia) {
	// trivia.kind, trivia.text, trivia.offset
}
```

Trivia kinds are `WHITESPACE`, `LINE_COMMENT`, `BLOCK_COMMENT`, `SHEBANG`, and `IGNORED`.
`IGNORED` represents source bytes deliberately skipped by the lexer outside the other categories, such as NBSP, zero-width space, and bidi formatting controls.

## Materialised Parser Tokens

`materialise_tokens(source)` copies the lexer's ring-buffer tokens into a stable parser-owned array.
It also recognises `#string` directives, so their bodies are represented by the same string token the parser will consume.

The returned `Parsed_Source` borrows `source` and owns a per-file identifier table and fallback pool.
Parser callers are expected to keep the source allocation alive and unchanged while using its tokens and syntax tree; the parser does not provide an owned-copy mode.
Unchanged identifier spellings can refer directly to source bytes, while normalised spellings use the fallback pool.
`release_parser_tree` does not free name storage because tokens remain available afterward.
Once the tree has been released and callers are finished with the tokens, `release_parser_names(*parsed)` frees the table and fallback pool; token identifier names are invalid after that call.
Standalone lexer tokens continue to own copied names unless optional storage was supplied.

With `ENABLE_TRIVIA=false`, `Parser_Token` aliases `Token`.
With trivia enabled, it extends the lexer token with a stable index and absolute, half-open byte boundaries.
`reconstruct_source` rebuilds the original source from the materialised token and trivia views.

## Syntax Tree Source Spans

`Parser_*` syntax node types form a parser-owned hierarchy with `Parser_Node` as their common base.
`Parser_Node` embeds the public `Code_Node` fields so common compiler metadata such as kind, flags, type, and location remains directly accessible.
Concrete parser nodes intentionally have their own layouts and parser-owned child pointer types; they must not be reinterpreted as concrete compiler `Code_*` nodes.

When trivia is enabled, every parser node directly contains `first_token` and `one_past_last_token`.
Together these fields identify the node's half-open token span without a table lookup.

AST nodes and parser-created child arrays share the `Pool` embedded in `Parsed_Source`.
Use `parser_node_allocator` for child arrays and `release_parser_tree` to invalidate and release the complete tree while retaining the materialised tokens and diagnostics.

## Complete File Parsing

`parse_file(source, fully_pathed_filename="")` parses declarations through end of input and returns an unparenthesised `Parser_Block` with block type `DATA_DECLARATIONS`. `Parsed_Source.fully_pathed_filename` preserves the caller-provided source identity; like `source` and token text, it is borrowed and must outlive the parsed result.

File parsing retains successful declarations around multiple malformed regions.
Truncated declarations remain in the partial tree and produce `INCOMPLETE`; recoverable syntax errors produce `RECOVERED`.
Empty input still returns a non-null, zero-width file block.

`examples/parse_how_to.jai` is the initial compatibility corpus.
It parses every `.jai` file under `how_to`, asserts a non-fatal file root and exact trivia round trip, and reports files that currently require recovery so unsupported syntax remains visible as parser coverage expands.
Its summary aggregates diagnostic kinds, expected and actual tokens, and recovery actions, followed by the structured first diagnostic for each affected file.
Zero-diagnostic file counts are reported separately from recovery and diagnostic totals, including the count of files recovering without a parser diagnostic.
ASCII-backed token kinds are rendered as source spellings and absent token fields as `<none>`.
The checked-in corpus baseline records relative filenames and diagnostic counts. Each run reports newly complete or newly recovering files, per-file improvements and regressions, and removed and added diagnostics separately.
The suggested next grammar candidate groups only the first diagnostic from each recovering file, avoiding recovery-cascade counts when prioritising work.

## Expression Parsing

`parse_expression(source)` currently parses identifiers; primitive number, string, boolean, and null literals; typed and untyped array and struct literals; here strings; placeholders; `context`; grouped expressions; prefix unary operators (including unary dot); binary operators; calls with positional and named arguments; member access; array subscripts; postfix pointer dereferences; casts; and expression and type queries.
The closing delimiter of a `#string` literal also terminates its containing declaration without requiring a semicolon; ordinary string declarations still require one, and an explicit semicolon after `#string` remains accepted.
In calls, `,,` separates ordinary arguments from temporary context replacements.
`Parser_Procedure_Call.context_modification` retains the source-spelled replacement expressions separately from `arguments_unsorted`, including named assignments and shorthand allocator values.
Postfix forms compose left-to-right, so calls, access, subscripts, casts, and dereferences can be chained.

Expression directives are described in the dedicated directive section below.
The resulting parser-owned node is returned in `Parsed_Source.root`.
Empty or truncated input returns `INCOMPLETE`; unsupported or trailing syntax returns `RECOVERED` with a structured diagnostic.

The compiler exports `value := ---` with a null declaration expression, so placeholder parsing currently has parser-shape tests but no direct `compiler_get_nodes` expression comparison.

Binary parsing uses the precedence classes derived by `../../print_precedences.jai`.
The expression parser preserves assignment-operator trees for compiler AST comparison and recovery; later statement parsing will own their statement-level semantics.
The differential suite covers every binary and assignment operator exposed by `Operator_Type`, compares every pair of precedence classes in both operand orders, and checks same-class associativity.
Ambiguous prefix, postfix, and parenthesised combinations are compared separately; unary dot binds to its immediate primary before later postfix access, as in `(.member).field`.

`parser_peek`, `parser_eat`, `parser_checkpoint`, and `parser_restore` provide the initial cursor API.
Materialised tokens can also be navigated with `token_at`, `previous_token`, and `next_token`.

## Type And Declaration Parsing

`parse_declaration(source)` parses typed, inferred, constant, uninitialised, and compound declarations.
Compound declarations preserve their left-hand names as parser-owned comma-separated arguments and represent multiple initialiser expressions with a `Parser_Comma_Separated_Arguments` node.
In statement blocks, `out1, out2 = hello(1)` also produces a `Parser_Compound_Declaration`, matching the compiler's AST: it has two names and one right-hand expression, unlike comma-separated declaration initialisers.
Comma-separated assignment targets may also be indexed or member expressions, including compound operators such as `+=`; these use the same compiler-matching node shape.
Multiple right-hand expressions are retained as comma-separated arguments.

Supported types include named types, pointers, fixed arrays, array views, resizable arrays, procedure types, polymorphic variables with restrictions, and `#type` with `distinct` or `isa`.
Procedure types accept unnamed parameter types (including nested procedure, pointer and array types), empty `-> ()` return lists, and the source-spelled `#Context` type directive.
Procedure headers retain the source-spelled `#dump` modifier as `DEBUG_DUMP`.  The compiler emits a procedure's bytecode when compiling it; the parser only records the syntax flag.
Declaration metadata includes `$` and `$$` auto-bake flags, backticked scope modifiers, `#align` expressions, placeholder initialisation flags, and trailing notes.
Source-spelled `#no_reset` is a declaration attribute, not a scope directive: the parser records it as the compiler-matching `NO_RESET` flag.
For global variables, it retains compile-time values at runtime.
Truncated prefixes report an incomplete parse.

Declaration and type normalisers compare parser nodes with compiler nodes inside intercepted child workspaces.
Context-generated flags such as `IS_GLOBAL` are intentionally excluded from syntax comparisons.

## Statement And Block Parsing

`parse_block(source)` parses imperative brace blocks, while `parse_declaration_block(source)` restricts a brace block to declarations and marks it as `DATA_DECLARATIONS`.
Explicit braces carry the compiler-compatible `IS_PARENTHESIZED` node flag; single-statement control-flow bodies are represented by unparenthesised parser-owned blocks.

Supported statements include expressions, declarations, multi-value returns, `while`, collection and range `for`, `if`, expression-form `ifx`, switch-style `case` (including a terminal bare `case;`), `defer`, `using`, `push_context`, `break`, `continue`, and `remove`.
Value-form `ifx` may omit its `else` branch; its parsed node retains a null `else_block`, so the compiler can supply the result type's default value.
It may also omit the `then` branch when `else` follows the condition immediately; the parsed node then retains a null `then_block`.
Both value branches may be omitted when the condition ends at an expression boundary; the parsed `ifx` retains null `then_block` and `else_block` nodes.
Expression-form `#ifx` uses the same value branches and retains both `IS_STATIC` and `IS_IFX` flags.
Statement-leading `#this(...)` calls use expression parsing, so their postfix arguments are retained, including inside block-bodied quick lambdas.
Call-level `inline` and `no_inline` prefixes set `INLINE_YES` and `INLINE_NO` on procedure-call nodes, including calls inside static branches.
Parenthesised `if` and `while` conditions remain expressions before a braced body, including comparisons, modulo and logical operations, and bare pointer truth tests; typed procedure headers retain their own syntax.
Declarations initialised by `ifx` with braced `then` and `else` value branches can omit the trailing semicolon before the next statement; an explicit semicolon is also accepted.
This includes named loop conditions and iterators, named for-expansion selectors, independently combined literal reverse and pointer iteration flags, `#complete`, `#through`, backticked return/defer, and `push_context,defer_pop` forms.

Blocks retain parent and owning-statement links.
Statement recovery inserts missing semicolons without consuming the next statement, synchronises at statement starts and closing braces, and synthesises a closing brace for truncated input.

## Procedure And Aggregate Parsing

Procedure definitions reuse the procedure-type header parser and attach parser-owned `Parser_Procedure_Body` and `Parser_Block` nodes.
Headers preserve named, polymorphic, `using`, defaulted, and vararg parameters; named or unnamed returns; foreign library and symbol names; and written flags such as `inline`, `#expand`, `#compile_time`, `#no_context`, and `#c_call`.
Operator declarations use the same declaration and procedure nodes, retaining exact names for unary and binary operators, compound assignments, and `[]`, `[]=`, or `*[]`; procedure modifiers and bodies follow the ordinary header path.
Focused and compiler differential fixtures cover all 39 overloadable lexer spellings: the single-character arithmetic, comparison, logical, and bitwise operators; equality, ordered comparison, logical, shift, and rotate operators; every corresponding assignment token; and the three subscript forms.
User overloads of `=` and `.` are the two excluded spellings.
Quick procedures support zero, one, or multiple inferred parameters and both expression and block bodies; expression bodies contain a synthetic return marked `AUTO_INSERTED_FOR_QUICK_LAMBDA`.

`Parser_Struct` represents both structs and unions, with `.UNION` in `textual_flags`.
Parameterized aggregates retain their parameter declarations in a `STRUCT_ARGUMENTS` block, while fields and constants remain in the `DATA_DECLARATIONS` body.
Declaration-form `using` fields retain the wrapped struct declaration whose subfields become accessible in the containing scope.
Both `#as using field: Struct_Type` and `using #as field: Struct_Type` mark that declaration with `IS_MARKED_AS_AS`, preserving the field selected for implicit casts to and from the containing aggregate.
`using,except` and `using,only` retain their compiler-compatible filter type and expression on struct fields, statements, named imports, and procedure parameters.
`using enum u16 { ... }` ends at its closing brace or an explicit semicolon before the next statement; ordinary `using` expressions still require a semicolon.
Parenthesised name lists become arrays of string literals, while array literals, named arrays, and `#run` expressions remain source-spelled filter expressions.
The advanced-using guide still recovers at `using,map`, which is not yet supported.
Aggregate field default assignments such as `w: float; w = 1;` and `info.flavor = "chocolate";` remain ordered binary-expression statements. Bare assignment identifiers and the base identifiers of dotted assignments link back to their matching parser-owned field declarations, including `#as using` fields.
`Parser_Enum` represents enums and enum flags, including underlying types, `#complete`, `#specified`, explicit values, and bare members.
Bare enum members also retain their identifier nodes inside braced, nested, and single-statement static `#if` branches.
Interface constraints use the compiler's `$T/interface Constraint` type-instantiation form and set `.INTERFACE`.

Aggregate layout modifiers preserve the compiler's textual flags.
Trailing notes remain attached to the containing declaration, matching the raw compiler AST.
Direct differential comparisons omit asynchronous procedure body pointers and semantically finalised aggregate alignment; focused parser tests cover those parser-owned fields.

## Directive Parsing

The parser has a parser-owned counterpart for each of the 20 public `Code_Directive_*` structures: through, overlay, procedure name, load, bytes, code, poke name, add context, context type, location, library, wildcard, exists, insert, run, import, modify, scope, module parameters, and bake.

Source parsing covers:

- `#char "x"` as the compiler-compatible numeric `Parser_Literal`, using the lexer's evaluated string byte; `#filepath` as a string literal containing the directory of `fully_pathed_filename`; and payload-free `#this` as the compiler's `DIRECTIVE_THIS` node kind.
- `#caller_code` as `Parser_Directive_Code` with the compiler's unnamed caller-code flag and a null expression.  It is accepted as a primary expression, so legal macro default arguments retain the compiler AST shape.
- `#if` in imperative, file, and aggregate declaration contexts, represented by `Parser_If` with `IS_STATIC`; its branch blocks retain the surrounding block mode, including enum member grammar.
- `#placeholder Name` file declarations, represented by `Parser_Placeholder` with the source-spelled name.  This is distinct from the `---` uninitialised-value placeholder.
- Prefix `#as using name: Type` aggregate fields and the equivalent `using #as name: Type` spelling, represented by `Parser_Using` around a declaration marked `IS_MARKED_AS_AS` for implicit casting.
- `#asm` statement blocks with optional feature names.  `Parser_Asm` stores ordered parser-owned `Parser_Asm_Feature` records, a balanced body token span, and ordered `Parser_Asm_Statement` nodes without overlaying the compiler's opaque payload fields.  Each feature retains a `Parser_Ident` and an exact token span; bare blocks retain an empty feature list.  `enclosing_scope` points to the surrounding high-level `Parser_Block`, so sibling assembly blocks share one scope while assembly braces do not create a lexical scope; register binding remains deferred to semantic analysis.  Generic statement dispatch accepts `#asm` directly in single-statement control-flow branches, including `#if ... #asm { ... } else #asm { ... }`, while retaining that surrounding scope.  Identifier-led instruction statements retain an open-ended mnemonic, optional fixed or polymorphic `Parser_Asm_Mnemonic_Size`, and top-level comma-separated operand spans; operand internals remain `UNPARSED`.  Missing terminal semicolons are diagnosed at the closing brace.  Parser-owned register declaration, register pinning, memory operand, value, and source-spelled modifier records preserve exact token spans.  The ordinary lexer stream is lossless for the assembly grammar: `===` is one token; fixed mnemonic suffixes such as `.8` and `.64` are leading-dot `NUMBER` tokens; polymorphic suffixes such as `?BITS` and `?T` are `?` plus `IDENT`; signs, `!`, `&`, `&*`, brackets, and declaration colons remain ordinary tokens; comments remain trivia.  No contextual assembly tokens are introduced, so ordinary member access and query tokenisation remain unchanged.
- `#code`, `#code,null`, and `#code,typed`, preserving expression, declaration, and block payload node kinds.
- `#run`, `#run,stallable`, and `#run,host`, with expression or block payloads, including `-> Return_Type { ... }` bodies.  Expression payloads set `HAS_IMPLICIT_RETURN_TYPES`; block payloads do not.  Typed blocks retain their procedure header and return declaration.  A block-form `#run` ends at its closing brace in a statement or declaration; a semicolon is optional there but remains required for expression-form `#run` statements.  `host` uses the compiler's unnamed `0x10` run flag and is mutually exclusive with `stallable`.
- `#assert condition` with an optional quoted message, lowered to `Parser_Directive_Run` with `ASSERTION` and `HAS_IMPLICIT_RETURN_TYPES`; the condition remains its expression and the message is retained in `assertion_string`.  This works in procedures, static branches, expansions, and module scope without executing assertions in the parser.
- `#insert`, optional scope and loop-control replacements, and `-> Return_Type { ... }` implicit-run bodies.  An empty `scope()` retains a null scope redirection; `scope(expression)` retains the expression.  Block-bodied short-form inserts terminate at the closing brace without a required semicolon; expression-form inserts still require one as statements.
- `#import` with `file`, `dir`, or `string`, plus module and program parameter calls.  `#import,string` accepts a quoted string or a `#string` here-string body; a standalone import requires a following semicolon, including after a here-string delimiter.
- `#library` with `system`, `no_static_library`, and `link_always`.
- `#load`, `#bytes`, `#procedure_name`, `#exists`, location and caller-location queries, and poke-name forms.
- `#procedure_of_call target(arguments)` as a `Parser_Procedure_Call` marked `RETURNS_PROCEDURE_POINTER_ONLY`, matching the compiler for ordinary and type-valued arguments.
- `#through`, `#overlay`, `#add_context`, `#modify`, `#scope_export`, `#scope_file`, and `#module_parameters`.
- `#bake_constants` and `#bake_arguments` call forms.

The raw compiler AST exposes a few distinctions that are not named source flags.
File and directory imports set an unnamed `0x4` bit, while string imports set `UNSHARED`. `link_always` is accepted but does not set `LINK_ALWAYS` in raw syntax trees.
`DYNAMIC_LIBRARY_UNAVAILABLE`, implicit code, run assertion metadata, insert expansion, wildcard indices, and internal scope are assigned during later compiler processing.

`Code_Asm` is public only as an opaque layout containing `b1`, `b2`, and `b3`; instruction, operand, and register data are not exposed to high-level metaprogramming.
The parser recognises instruction envelopes with mnemonics, optional size suffixes, and comma-separated operand spans; operand internals such as registers, memory addressing, and modifiers remain `UNPARSED`.
It also preserves the full assembly body as source.
Compiler comparisons cover the `.ASM` node kind and surrounding tree placement, not the opaque compiler payload or parser-owned operand internals.

`Code_Directive_Context_Type` has no source payload; its source spelling is `#Context`, while the compiler rejects `#context_type` as a source directive.
Standalone `#wildcard` and generic `#bake` are likewise rejected by the current compiler; parser-owned forms remain available for editor recovery and public-node handling.
`DIRECTIVE_THIS`, `DIRECTIVE_PLACE`, and `DIRECTIVE_COMPILE_TIME` have no corresponding public `Code_Directive_*` structure; their syntax is represented through other nodes or compiler processing.

Differential fixtures compare every compiler-accepted expression or contextual form available through `compiler_get_nodes`.
Scope and add-context use child workspaces because they are file-only.
Module parameters are validated by compiling the parser module itself, since compiler-added strings are not module-file scope.
Focused tests cover parser-owned fields that compiler messages omit, including modify ownership, poke-name source expressions, module-parameter bodies, wildcard placeholders, and implicit insert-run procedure headers.

## Error Recovery

The source token array is immutable after materialisation.
When a required token is absent, the parser records a zero-width `Synthetic_Token` at the current token boundary and adds a `Parse_Diagnostic` describing the expected and actual token and the recovery action.
Synthetic tokens are kept separately from source tokens, so token indices remain stable and `reconstruct_source` always reproduces only the original input.

Each `Parse_Diagnostic` has a primary token span and message.
Its `related_information` slice can contain zero or more additional span/message pairs, matching the compiler's convention of reporting an `Error:` location followed by related `Info:` locations.
`render_diagnostic_line` expands tabs to 4-column tab stops and returns the expanded source line plus a caret line covering the diagnostic's exclusive column range.

Recovery loops use `parser_progress_guard` and `parser_ensure_progress`, so a failed parse cannot repeatedly inspect the same non-EOF token.
`parser_synchronize` defines restart boundaries for expression, statement, declaration, and block contexts.
Synchronisation stops before the boundary token so its enclosing parser remains responsible for consuming delimiters such as `,`, `;`, `)`, `]`, and `}`.
Nested parentheses, brackets, and braces are traversed before testing their internal tokens as restart boundaries.
Completing a recovered braced region returns control to the owning expression, statement, or declaration parser, preventing its contents from being reinterpreted in an enclosing scope.

Focused recovery fixtures cover selected section 13.1 truncations and malformed trailing text after `#this`, `#filepath`, and `#caller_code`.
They check nonfatal partial trees and selected flags, child counts, or diagnostics.
Separate synchronisation fixtures check that later declarations remain in their enclosing scopes; these tests do not cover every malformed form of each construct.

## Differential Tests

`examples/differential_test.jai` normalises parser and compiler ASTs into path-keyed syntax fields and reports every structural mismatch.
Its `assert_expression_fixture` macro accepts source text once and generates the matching `#code` argument with `#insert`, preventing the parser input and compiler oracle from drifting apart.
The harness keeps syntax and semantic normalisation separate, provides trivia round-trip fixtures, and includes intercepted child-workspace fixtures for typechecked declarations and file-level constructs.
Compiling the suite runs its compile-time AST and workspace fixtures; running the resulting executable is also required to verify structural-diff and compiler-diagnostic assertions.
Both checks pass after the diagnostic-location fixture correction; earlier compile-time fixture results alone did not establish runtime coverage.

For invalid-source fixtures, `capture_compiler_error` writes the supplied code to a temporary fixture, invokes `jai -x64`, and returns structured primary diagnostics with their related information.
`assert_compiler_error_message` and `assert_invalid_expression_compiler_message` provide concise assertions for common cases; pass `log_output=true` to `capture_compiler_error` when the complete compiler rendering is useful.
Captured compiler locations use exclusive `l0`, `c0`, `l1`, and `c1` ranges; the redirected caret run determines the end column.
Compiler fixtures must use spaces because the compiler currently aligns carets as though each source tab occupied one column.
