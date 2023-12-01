Nonterminals
  grammar
  expr expr1 expr2
  value
  access_op
  access_op_key
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
  %% other
  '(' ')' '[' ']' ',' 
  %% lambda tokens
  'fn' '->' 'end'
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
expr -> expr '-' expr1 : {'-', '$1', '$3'}.
expr -> expr1 : '$1'.
expr1 -> expr1 '*' expr2 : {'*', '$1', '$3'}.
expr1 -> expr1 '/' expr2 : {'/', '$1', '$3'}.
expr1 -> expr2 : '$1'.
expr2 -> value : '$1'.

%% Handle multiple levels of access operators: @data["key"], @data["key"]["key2"]
access_op -> identifier '[' access_op_key ']': {access_op, '$1', '$3'}.
access_op -> env_var '[' access_op_key ']': {access_op, '$1', '$3'}.
access_op -> access_op '[' access_op_key ']': {access_op, '$1', '$3'}.

access_op_key -> ascii_string : '$1'.
access_op_key -> identifier : '$1'.

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
