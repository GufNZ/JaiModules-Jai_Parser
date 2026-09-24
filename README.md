# Jai_Parser
## Lexer

This module starts from `Jai_Lexer` and adds current parser-oriented tokenisation.

The default import retains the original `Token` and `Lexer` memory layouts:

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

The returned `Parsed_Source` borrows `source`.
Parser callers are expected to keep the source allocation alive and unchanged while using its tokens and syntax tree; the parser does not provide an owned-copy mode.

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

## Expression Parsing

`parse_expression(source)` currently parses identifiers; primitive number, string, boolean, and null literals; typed and untyped array and struct literals; here strings; placeholders; `context`; grouped expressions; prefix unary operators (including unary dot); binary operators; calls with positional and named arguments; member access; array subscripts; postfix pointer dereferences; casts; and expression and type queries.
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

Supported types include named types, pointers, fixed arrays, array views, resizable arrays, procedure types, polymorphic variables with restrictions, and `#type` with `distinct` or `isa`.
Declaration metadata includes `$` and `$$` auto-bake flags, backticked scope modifiers, `#align` expressions, placeholder initialisation flags, and trailing notes.

Declaration and type normalisers compare parser nodes with compiler nodes inside intercepted child workspaces.
Context-generated flags such as `IS_GLOBAL` are intentionally excluded from syntax comparisons.

## Statement And Block Parsing

`parse_block(source)` parses imperative brace blocks, while `parse_declaration_block(source)` restricts a brace block to declarations and marks it as `DATA_DECLARATIONS`.
Explicit braces carry the compiler-compatible `IS_PARENTHESIZED` node flag; single-statement control-flow bodies are represented by unparenthesised parser-owned blocks.

Supported statements include expressions, declarations, multi-value returns, `while`, collection and range `for`, `if`, expression-form `ifx`, switch-style `case`, `defer`, `using`, `push_context`, `break`, `continue`, and `remove`.
This includes named loop conditions and iterators, reverse and pointer iteration, `#complete`, `#through`, backticked return/defer, and `push_context,defer_pop` forms.

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
Aggregate field default assignments such as `w: float; w = 1;` remain ordered binary-expression statements, and the assignment identifier links back to its matching parser-owned field declaration.
`Parser_Enum` represents enums and enum flags, including underlying types, `#complete`, `#specified`, explicit values, and bare members.
Interface constraints use the compiler's `$T/interface Constraint` type-instantiation form and set `.INTERFACE`.

Aggregate layout modifiers preserve the compiler's textual flags.
Trailing notes remain attached to the containing declaration, matching the raw compiler AST.
Direct differential comparisons omit asynchronous procedure body pointers and semantically finalised aggregate alignment; focused parser tests cover those parser-owned fields.

## Directive Parsing

The parser has a parser-owned counterpart for each of the 20 public `Code_Directive_*` structures: through, overlay, procedure name, load, bytes, code, poke name, add context, context type, location, library, wildcard, exists, insert, run, import, modify, scope, module parameters, and bake.

Source parsing covers:

- `#char "x"` as the compiler-compatible numeric `Parser_Literal`, using the lexer's evaluated string byte; `#filepath` as a string literal containing the directory of `fully_pathed_filename`; and payload-free `#this` as the compiler's `DIRECTIVE_THIS` node kind.
- `#caller_code` as `Parser_Directive_Code` with the compiler's unnamed caller-code flag and a null expression.  It is accepted as a primary expression, so legal macro default arguments retain the compiler AST shape.
- `#if` in imperative, file, and aggregate declaration contexts, represented by `Parser_If` with `IS_STATIC`; its branch blocks retain the surrounding block mode.
- `#placeholder Name` file declarations, represented by `Parser_Placeholder` with the source-spelled name.  This is distinct from the `---` uninitialised-value placeholder.
- Prefix `#as using name: Type` aggregate fields, represented by `Parser_Using` around a declaration marked `IS_MARKED_AS_AS`.  The `using #as` spelling remains part of the broader using-declaration work.
- `#asm` statement blocks with optional feature names.  `Parser_Asm` preserves the feature list and balanced body token span without interpreting assembly instructions.
- `#code`, `#code,null`, and `#code,typed`, with expression or block payloads.
- `#run` and `#run,stallable`, with expression or block payloads.
- `#insert`, optional scope and loop-control replacements, and `-> Return_Type { ... }` implicit-run bodies.
- `#import` with `file`, `dir`, or `string`, plus module and program parameter calls.
- `#library` with `system`, `no_static_library`, and `link_always`.
- `#load`, `#bytes`, `#procedure_name`, `#exists`, location and caller-location queries, and poke-name forms.
- `#through`, `#overlay`, `#add_context`, `#modify`, `#scope_export`, `#scope_file`, and `#module_parameters`.
- `#bake_constants` and `#bake_arguments` call forms.

The raw compiler AST exposes a few distinctions that are not named source flags.
File and directory imports set an unnamed `0x4` bit, while string imports set `UNSHARED`. `link_always` is accepted but does not set `LINK_ALWAYS` in raw syntax trees.
`DYNAMIC_LIBRARY_UNAVAILABLE`, implicit code, run assertion metadata, insert expansion, wildcard indices, and internal scope are assigned during later compiler processing.

`Code_Asm` is public only as an opaque layout containing `b1`, `b2`, and `b3`; instruction, operand, and register data are not exposed to high-level metaprogramming.
The parser therefore treats the assembly body as preserved source until the dedicated assembly grammar is implemented.
Differential tests compare the node kind and placement only.

`Code_Directive_Context_Type` has no source payload and the compiler rejects `#context_type` as a source directive.
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

Recovery loops use `parser_progress_guard` and `parser_ensure_progress` so a failed parse cannot repeatedly inspect the same non-EOF token.
`parser_synchronize` defines restart boundaries for expression, statement, declaration, and block contexts.
Synchronisation stops before the boundary token so its enclosing parser remains responsible for consuming delimiters such as `,`, `;`, `)`, `]`, and `}`.

## Differential Tests

`examples/differential_test.jai` normalises parser and compiler ASTs into path-keyed syntax fields and reports every structural mismatch.
Its `assert_expression_fixture` macro accepts source text once and generates the matching `#code` argument with `#insert`, preventing the parser input and compiler oracle from drifting apart.
The harness keeps syntax and semantic normalisation separate, provides trivia round-trip fixtures, and includes intercepted child-workspace fixtures for typechecked declarations and file-level constructs.

For invalid-source fixtures, `capture_compiler_error` writes the supplied code to a temporary fixture, invokes `jai -x64`, and returns structured primary diagnostics with their related information.
`assert_compiler_error_message` and `assert_invalid_expression_compiler_message` provide concise assertions for common cases; pass `log_output=true` to `capture_compiler_error` when the complete compiler rendering is useful.
Captured compiler locations use exclusive `l0`, `c0`, `l1`, and `c1` ranges; the redirected caret run determines the end column.
Compiler fixtures must use spaces because the compiler currently aligns carets as though each source tab occupied one column.
