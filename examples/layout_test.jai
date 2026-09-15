#import "Basic";

Original :: #import "Jai_Lexer";
Default  :: #import "Jai_Parser";
Extended :: #import "Jai_Parser"(ENABLE_TRIVIA=true);

#assert(size_of(Default.Token) == size_of(Original.Token));
#assert(size_of(Default.Lexer) == size_of(Original.Lexer));

main :: () {
	default_lexer: Default.Lexer;
	extended_lexer: Extended.Lexer;

	Default.set_input_from_string(*default_lexer, "(.*) <<");
	assert(Default.peek_next_token(*default_lexer).type == .PREFIX_DEREFERENCE);
	Default.eat_token(*default_lexer);
	assert(Default.peek_next_token(*default_lexer).type == .SHIFT_LEFT);

	Default.set_input_from_string(*default_lexer, "( .*)");
	assert(Default.peek_next_token(*default_lexer).type == #char "(");

	input :: " \tfoo\\  bar /* outer /* inner */ end */ 1_000 (.*) ptr // tail";
	Extended.set_input_from_string(*extended_lexer, input);

	token := Extended.peek_next_token(*extended_lexer);
	assert(token.type == .IDENT);
	assert(token.ident_value.name == "foobar");
	assert(token.original_text == "foo\\  bar");
	assert(token.preceding_trivia == " \t");
	Extended.eat_token(*extended_lexer);

	token = Extended.peek_next_token(*extended_lexer);
	assert(token.type == .NUMBER);
	assert(token.integer_value == 1000);
	assert(token.original_text == "1_000");
	assert(token.preceding_trivia == " /* outer /* inner */ end */ ");
	Extended.eat_token(*extended_lexer);

	token = Extended.peek_next_token(*extended_lexer);
	assert(token.type == .PREFIX_DEREFERENCE);
	assert(token.original_text == "(.*)");
	assert(token.preceding_trivia == " ");
	Extended.eat_token(*extended_lexer);

	token = Extended.peek_next_token(*extended_lexer);
	assert(token.type == .IDENT);
	assert(token.original_text == "ptr");
	assert(token.preceding_trivia == " ");
	Extended.eat_token(*extended_lexer);

	token = Extended.peek_next_token(*extended_lexer);
	assert(token.type == .END_OF_INPUT);
	assert(token.trailing_trivia == " // tail");
}
