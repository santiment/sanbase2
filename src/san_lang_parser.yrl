Nonterminals
  grammar
  expr 
  value
  comparison_op
  access_expr
  access_expr_key
  function_call
  function_call_args_list
  function_call_arg
  lambda_fn
  lambda_args
.

Terminals
  %% Types
  int float ascii_string
  %% vars and env vars
  identifier env_var
  %% arithmetic operators
  '+' '-' '*' '/'
  %% cmp operators
  '==' '!=' '<' '<=' '>' '>='
  %% other
  '(' ')' '[' ']' ',' 
  %% lambda tokens
  'fn' '->' 'end'
.

Rootsymbol
   grammar
.

%% Precedence
Left 100 '+'.
Left 100 '-'.
Left 200 '*'.
Left 200 '/'.

grammar -> expr : '$1'.

%% expr, expr1 and expr2 handle the precedence of the arithmetic operators
%% Currently the only way of combining multiple values is by using the
%% arithmetic operators: @data["key"] + pow(2, 10)
expr -> expr '+' expr : {'+', '$1', '$3'}.
expr -> expr '-' expr : {'-', '$1', '$3'}.
expr -> expr '*' expr : {'*', '$1', '$3'}.
expr -> expr '/' expr : {'/', '$1', '$3'}.
expr -> value : '$1'.

%% Values
value -> int : '$1'.
value -> float : '$1'.
value -> ascii_string : '$1'.
value -> env_var : '$1'.
value -> access_expr : '$1'.
value -> function_call : '$1'.
value -> identifier : '$1'.

%% Handle multiple levels of access operators: @data["key"], @data["key"]["key2"]
access_expr -> identifier '[' access_expr_key ']': {access_expr, '$1', '$3'}.
access_expr -> env_var '[' access_expr_key ']': {access_expr, '$1', '$3'}.
access_expr -> access_expr '[' access_expr_key ']': {access_expr, '$1', '$3'}.

access_expr_key -> ascii_string : '$1'.
access_expr_key -> identifier : '$1'.

%% comparison expressions
comparison_op -> '==' : '$1'.
comparison_op -> '!=' : '$1'.
comparison_op -> '<' : '$1'.
comparison_op -> '<=' : '$1'.
comparison_op -> '>' : '$1'.
comparison_op -> '>=' : '$1'.

%% Lambda function
lambda_fn -> 'fn' lambda_args '->' expr 'end' : {lambda_fn, '$2', '$4'}.
lambda_args -> identifier ',' lambda_args : ['$1' | '$3'].
lambda_args -> identifier : ['$1'].

%% Named function call -- empty and with args.
function_call -> identifier '('  ')' : {function_call, '$1', []}.
function_call -> identifier '(' function_call_args_list ')' : {function_call, '$1', '$3'}.

%% Arguments list with at least 1 argument. Function calls with 0 arguments are
%% handled directly by the function_call rule.
function_call_args_list -> function_call_arg ',' function_call_args_list : ['$1' | '$3'].
function_call_args_list -> function_call_arg : ['$1'].

function_call_arg -> value : '$1'.
function_call_arg -> lambda_fn : '$1'.
 
Erlang code.
