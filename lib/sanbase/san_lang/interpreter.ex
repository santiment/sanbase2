defmodule Sanbase.SanLang.Interpreter do
  alias Sanbase.SanLang.Environment

  # Terminal values
  def eval({:int, _, value}, _env), do: value
  def eval({:float, _, value}, _env), do: value
  def eval({:ascii_string, _, value}, _env), do: value

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

  def eval({:access_op, {:env_var, _, "@" <> env_var}, {:ascii_string, _, key}}, env) do
    env_var = Environment.get_env_binding(env, env_var)
    Map.get(env_var, key)
  end
end
