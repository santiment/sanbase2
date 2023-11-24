Nonterminals
  grammar
  expr expr1 expr2
  value
  access_op
  function_call
  arguments_list
  argument
.

Terminals
  %% Types
  int float ascii_string
  %% 
  identifier env_var
  '+' '-' '*' '/'
  '='
  '(' ')' '[' ']'
  ','
.

Rootsymbol
   grammar
.

grammar -> expr : '$1'.

value -> int : '$1'.
value -> float : '$1'.
value -> ascii_string : '$1'.
value -> env_var : '$1'.
value -> access_op : '$1'.
value -> function_call : '$1'.
value -> identifier : '$1'.

%% expr, expr1 and expr2 handle the precedence of the arithmetic operators
%% Currently the only way of combining multiple values is by using the
%% arithmetic operators: @data["key"] + pow(2, 10)
expr -> expr '+' expr1 : {'+', '$1', '$3'}.
expr -> expr '-' expr1 : {'+', '$1', '$3'}.
expr -> expr1 : '$1'.
expr1 -> expr1 '*' expr2 : {'*', '$1', '$3'}.
expr1 -> expr1 '/' expr2 : {'/', '$1', '$3'}.
expr1 -> expr2 : '$1'.
expr2 -> value : '$1'.

%% Handle multiple levels of access operators: @data["key"], @data["key"]["key2"]
access_op -> identifier '[' ascii_string ']': {access_op, '$1', '$3'}.
access_op -> env_var '[' ascii_string ']': {access_op, '$1', '$3'}.
access_op -> access_op '[' ascii_string ']': {access_op, '$1', '$3'}.

%% Empty function call.
function_call -> identifier '('  ')' : {function_call, '$1', []}.
function_call -> identifier '(' arguments_list ')' : {function_call, '$1', '$3'}.

%% Arguments list with at least 1 argument. Function calls with 0 arguments are
%% handled directly by the function_call rule.
arguments_list -> value ',' arguments_list : ['$1' | '$3'].
arguments_list -> value : ['$1'].
 
Erlang code.
