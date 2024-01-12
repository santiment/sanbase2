defmodule Sanbase.SanLang.Interpreter do
  alias Sanbase.SanLang
  alias Sanbase.SanLang.Environment

  defmodule UnboundError do
    defexception [:message]
  end

  defmodule UndefinedFunctionError do
    defexception [:message]
  end

  # Terminal values
  def eval({:int, _, value}, _env), do: value
  def eval({:float, _, value}, _env), do: value
  def eval({:ascii_string, _, value}, _env), do: value
  def eval({:env_var, _, _} = env_var, env), do: eval_env_var(env_var, env)
  def eval({:identifier, _, _} = identifier, env), do: eval_identifier(identifier, env)
  def eval({:lambda_fn, _args, _body} = lambda, env), do: eval_lambda_fn(lambda, env)
  def eval({:list, _} = list, env), do: eval_list(list, env)

  def eval({{boolean_op, _}, _, _} = boolean_expr, env) when boolean_op in [:and, :or],
    do: eval_boolean_expr(boolean_expr, env)

  def eval({boolean, _}, _env) when boolean in [true, false], do: boolean

  # Arithemtic
  def eval({:+, l, r}, env), do: eval(l, env) + eval(r, env)
  def eval({:-, l, r}, env), do: eval(l, env) - eval(r, env)
  def eval({:*, l, r}, env), do: eval(l, env) * eval(r, env)
  def eval({:/, l, r}, env), do: eval(l, env) / eval(r, env)

  # Access Operator
  def eval({:access_expr, {:access_expr, _, _} = inner_access_expr, {:ascii_string, _, key}}, env) do
    env_var = eval(inner_access_expr, env)
    Map.get(env_var, key)
  end

  # Comparison
  def eval({{:comparison_expr, {op, _}}, lhs, rhs}, env) when op in ~w(== != < > <= >=)a,
    do: apply(Kernel, op, [eval(lhs, env), eval(rhs, env)])

  # Named Function Calls
  def eval({:function_call, {:identifier, _, function_name}, args}, env) do
    eval_function_call(function_name, args, env)
  end

  def eval({:access_expr, env_var_or_identifier, key}, env) do
    # The acessed type is an env var or an identifier
    map = eval(env_var_or_identifier, env)
    # The key can be a string, or an identifier if used from inside a map/filter/reduce
    key = eval(key, env)
    Map.get(map, key)
  end

  def eval_list({:list, list_elements}, env) do
    Enum.map(list_elements, fn x -> eval(x, env) end)
  end

  # Boolean expressions
  def eval_boolean_expr({{op, _}, lhs, rhs}, env) when op in [:and, :or] do
    lhs = eval(lhs, env)
    rhs = eval(rhs, env)

    cond do
      not is_boolean(lhs) ->
        raise ArgumentError, message: "Left hand side of #{op} must be a boolean"

      not is_boolean(rhs) ->
        raise ArgumentError, message: "Right hand side of #{op} must be a boolean"

      true ->
        apply(:erlang, op, [lhs, rhs])
    end
  end

  @supported_functions SanLang.Kernel.__info__(:functions)
                       |> Enum.map(fn {name, _arity} -> to_string(name) end)
  defp eval_function_call(function_name, args, env)
       when is_binary(function_name) and function_name in @supported_functions do
    args =
      Enum.map(
        args,
        fn
          # The lambda evaluation is postponed until the lambda is called from
          # within the map/filter/reduce body
          {:lambda_fn, _args, _body} = lambda -> lambda
          # The rest of the arguments can be evaluated before they are passed to the
          # function
          x -> eval(x, env)
        end
      )

    # Each of the functions in the Kernel module takes an environment as the last argument
    args = args ++ [env]
    # We've already checked that the function name exists. Somethimes there are strange
    # errors during tests that :map_keys is not an existing atom, even though there is
    # such a function in the SanLang.Kernel module
    # credo:disable-for-next-line
    apply(SanLang.Kernel, String.to_atom(function_name), args)
  end

  defp eval_function_call(function_name, _args, _env) when is_binary(function_name) do
    raise UndefinedFunctionError, message: "Function #{function_name} is not supported"
  end

  defp eval_env_var({:env_var, _, "@" <> key}, env) do
    case Environment.get_env_binding(env, key) do
      {:ok, value} -> value
      {:error, error} -> raise UnboundError, message: error
    end
  end

  defp eval_identifier({:identifier, _, key}, env) do
    case Environment.get_local_binding(env, key) do
      {:ok, value} -> value
      {:error, error} -> raise UnboundError, message: error
    end
  end

  defp eval_lambda_fn({:lambda_fn, _args, body}, env) do
    eval(body, env)
  end
end
