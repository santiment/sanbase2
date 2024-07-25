Definitions.

INT               = [0-9]+
FLOAT             = [0-9]+\.[0-9]+
STRING            = \"[^\"]*\"
IDENTIFIER        = [a-zA-Z][a-zA-Z0-9_]*
ENV_VAR           = [@][a-zA-Z][a-zA-Z0-9_]*
WHITESPACE        = [\s\t\n\r]
KW_FN             = fn
KW_END            = end
KW_AND            = and
KW_OR             = or
TRUE              = true
FALSE             = false

Rules.
\+                : {token, {'+',  TokenLoc}}.
\-                : {token, {'-',  TokenLoc}}.
\*                : {token, {'*',  TokenLoc}}.
\/                : {token, {'/',  TokenLoc}}.
\>                : {token, {'>',  TokenLoc}}.
\<                : {token, {'<',  TokenLoc}}.
\>=               : {token, {'>=',  TokenLoc}}.
\<=               : {token, {'<=',  TokenLoc}}.
\==               : {token, {'==',  TokenLoc}}.
\!=               : {token, {'!=',  TokenLoc}}.
\(                : {token, {'(',  TokenLoc}}.
\)                : {token, {')',  TokenLoc}}.
\[                : {token, {'[',  TokenLoc}}.
\]                : {token, {']',  TokenLoc}}.
\-\>              : {token, {'->', TokenLoc}}.
\,                : {token, {',',  TokenLoc}}.
\"                : {token, {'"',  TokenLoc}}.
{TRUE}            : {token, {true, TokenLoc}}.
{FALSE}           : {token, {false, TokenLoc}}.
{KW_FN}           : {token, {'fn', TokenLoc}}.
{KW_END}          : {token, {'end', TokenLoc}}.
{KW_AND}          : {token, {'and', TokenLoc}}.
{KW_OR}           : {token, {'or', TokenLoc}}.
{ENV_VAR}         : {token, {env_var, TokenLoc, to_binary(TokenChars)}}.
{STRING}          : {token, {ascii_string, TokenLoc, strip_quoted_ascii_string(TokenChars)}}.
{IDENTIFIER}      : {token, {identifier, TokenLoc, to_binary(TokenChars)}}.
{FLOAT}           : {token, {float, TokenLoc, to_float(TokenChars)}}.
{INT}             : {token, {int, TokenLoc, to_integer(TokenChars)}}.
{WHITESPACE}+     : skip_token.

Erlang code.

to_binary(Chars) ->
    list_to_binary(Chars).

to_integer(Chars) ->
    list_to_integer(Chars).

to_float(Chars) ->
    list_to_float(Chars).

strip_quoted_ascii_string(QuotedString) ->
    % if there are non-ascii characters in the string, throw an error
    [error(string_with_non_ascii_characters) || U <- QuotedString, U > 127],
    list_to_binary(lists:sublist(QuotedString, 2, length(QuotedString) - 2)).
