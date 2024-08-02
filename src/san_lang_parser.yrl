Nonterminals
  grammar
  expr
  value
  list list_elements
  dual_arithmetic_op mult_arithmetic_op
  boolean_literal and_op or_op
  comparison_rel_op comparison_comp_op
  access_expr access_expr_key
  function_call function_call_args_list function_call_arg
  lambda_fn lambda_args
.

Terminals
  %% boolean values
  'true' 'false'
  %% Types
  int float ascii_string
  %% vars and env vars
  identifier env_var
  %% arithmetic operators
  '+' '-' '*' '/'
  %% comparison operators
  '==' '!=' '<' '<=' '>' '>='
  %% other
  '(' ')' '[' ']' ','
  %% lambda tokens
  'fn' '->' 'end'
  %% boolean operators
  'and' 'or'
.

Rootsymbol
   grammar
.

%% Precedence
Left 50  or_op.
Left 60  and_op.
Left 100 comparison_comp_op. %% == !=
Left 200 comparison_rel_op.  %% > < >= <=
Left 300 dual_arithmetic_op. %% + -
Left 400 mult_arithmetic_op. %% * /

grammar -> expr : '$1'.

%% Handle parentheses
expr -> '(' expr ')' : '$2'.

%% Handle arithmetic operations
expr -> expr dual_arithmetic_op expr : {'$2', '$1', '$3'}.
expr -> expr mult_arithmetic_op expr : {'$2', '$1', '$3'}.
expr -> expr and_op expr : {'$2', '$1', '$3'}.
expr -> expr or_op expr : {'$2', '$1', '$3'}.

%% Handle comparison operators
expr -> expr comparison_comp_op expr : {'$2', '$1', '$3'}.
expr -> expr comparison_rel_op expr : {'$2', '$1', '$3'}.

expr -> value : '$1'.

%% Values
value -> int : '$1'.
value -> float : '$1'.
value -> ascii_string : '$1'.
value -> env_var : '$1'.
value -> access_expr : '$1'.
value -> function_call : '$1'.
value -> identifier : '$1'.
value -> boolean_literal : '$1'.
value -> list : '$1'.

%% booleans
boolean_literal -> 'true' : '$1'.
boolean_literal -> 'false' : '$1'.
and_op -> 'and' : '$1'.
or_op -> 'or' : '$1'.

%% handle multiple levels of access operators: @data["key"], @data["key"]["key2"]
access_expr -> identifier '[' access_expr_key ']' : {access_expr, '$1', '$3'}.
access_expr -> env_var '[' access_expr_key ']' : {access_expr, '$1', '$3'}.
access_expr -> access_expr '[' access_expr_key ']' : {access_expr, '$1', '$3'}.

access_expr_key -> ascii_string : '$1'.
access_expr_key -> identifier : '$1'.

%% arithmetic operator
dual_arithmetic_op -> '+' : '+'.
dual_arithmetic_op -> '-' : '-'.
mult_arithmetic_op -> '*' : '*'.
mult_arithmetic_op -> '/' : '/'.

%% comparison operator
comparison_comp_op -> '==' : {comparison_expr, '$1'}.
comparison_comp_op -> '!=' : {comparison_expr, '$1'}.
comparison_rel_op -> '<' : {comparison_expr, '$1'}.
comparison_rel_op -> '<=' : {comparison_expr, '$1'}.
comparison_rel_op -> '>' : {comparison_expr, '$1'}.
comparison_rel_op -> '>=' : {comparison_expr, '$1'}.

%% Lists
list -> '[' ']' : {list, []}.
list -> '[' list_elements ']' : {list, '$2'}.
list_elements -> value ',' list_elements : ['$1' | '$3'].
list_elements -> value : ['$1'].

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
