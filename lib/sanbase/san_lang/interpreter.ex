defmodule Sanbase.SanLang.Interpreter do
  alias Sanbase.SanLang.Environment

  # Terminal values
  def eval({:int, _, value}, _env), do: value
  def eval({:float, _, value}, _env), do: value
  def eval({:ascii_string, _, value}, _env), do: value
  def eval({:env_var, _, "@" <> env_var}, env), do: Environment.get_env_binding(env, env_var)

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

  def eval({:access_op, {:env_var, _, _} = env_var, {:ascii_string, _, key}}, env) do
    env_var = eval(env_var, env)
    Map.get(env_var, key)
  end

  # Named Function Calls
  def eval({:function_call, {:identifier, _, function_name}, args}, env) do
    eval_function_call(function_name, args, env)
  end

  defp eval_function_call("pow", args, env) when length(args) == 2 do
    args = Enum.map(args, &eval(&1, env))
    apply(Sanbase.SanLang.Kernel, :pow, args)
  end
end
