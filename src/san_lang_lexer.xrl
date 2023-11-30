Definitions.

INT           = [0-9]+
FLOAT         = [0-9]+\.[0-9]+
STRING        = \"[^\"]*\"
IDENTIFIER    = [a-zA-Z][a-zA-Z0-9_]*
ENV_VAR       = [@][a-zA-Z][a-zA-Z0-9_]*
WHITESPACE    = [\s\t\n\r]
LAMBDA_START  = fn
LAMBDA_END    = end

Rules.
\+                : {token, {'+',  TokenLine}}.
\-                : {token, {'-',  TokenLine}}.
\*                : {token, {'*',  TokenLine}}.
\/                : {token, {'/',  TokenLine}}.
\(                : {token, {'(',  TokenLine}}.
\)                : {token, {')',  TokenLine}}.
\[                : {token, {'[',  TokenLine}}.
\]                : {token, {']',  TokenLine}}.
\-\>              : {token, {'->', TokenLine}}.
\,                : {token, {',',  TokenLine}}.
\"                : {token, {'"',  TokenLine}}.
{LAMBDA_START}    : {token, {'fn', TokenLine}}.
{LAMBDA_END}      : {token, {'end', TokenLine}}.
{ENV_VAR}         : {token, {env_var, TokenLine, to_binary(TokenChars)}}.
{STRING}          : {token, {ascii_string, TokenLine, strip_quoted_ascii_string(TokenChars)}}.
{IDENTIFIER}      : {token, {identifier, TokenLine, to_binary(TokenChars)}}.
{FLOAT}           : {token, {float, TokenLine, to_float(TokenChars)}}.
{INT}             : {token, {int, TokenLine, to_integer(TokenChars)}}.
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
