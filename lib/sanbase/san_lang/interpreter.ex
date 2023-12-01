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
  # The true evaluation is called from withing the Kernel.map/filter/etc. functions
  def eval({:lambda_fn, _args, _body} = lambda, _env), do: lambda

  # Arithemtic
  def eval({:+, l, r}, env), do: eval(l, env) + eval(r, env)
  def eval({:-, l, r}, env), do: eval(l, env) - eval(r, env)
  def eval({:*, l, r}, env), do: eval(l, env) * eval(r, env)
  def eval({:/, l, r}, env), do: eval(l, env) / eval(r, env)

  # Access Operator
  def eval({:access_op, {:access_op, _, _} = inner_access_op, {:ascii_string, _, key}}, env) do
    env_var = eval(inner_access_op, env)
    Map.get(env_var, key)
  end

  def eval({:access_op, env_var_or_identifier, {:ascii_string, _, key}}, env) do
    map = eval(env_var_or_identifier, env)
    Map.get(map, key)
  end

  # Named Function Calls
  def eval({:function_call, {:identifier, _, function_name}, args}, env) do
    eval_function_call(function_name, args, env)
  end

  def true_eval_lambda_fn({:lambda_fn, _args, _body} = lambda, env),
    do: eval_lambda_fn(lambda, env)

  @supported_functions SanLang.Kernel.__info__(:functions)
                       |> Enum.map(fn {name, _arity} -> to_string(name) end)
  defp eval_function_call(function_name, args, env)
       when is_binary(function_name) and function_name in @supported_functions do
    args = Enum.map(args, &eval(&1, env)) ++ [env]
    apply(SanLang.Kernel, String.to_existing_atom(function_name), args)
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
