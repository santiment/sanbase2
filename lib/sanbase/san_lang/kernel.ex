defmodule Sanbase.SanLang.Kernel do
  alias Sanbase.SanLang.Environment
  alias Sanbase.SanLang.Interpreter

  def pow(base, pow, _env) when is_number(base) and is_number(pow) do
    base ** pow
  end

  def div(dividend, divisor, _env) when is_number(dividend) and is_number(divisor) do
    div(dividend, divisor)
  end

  def map_keys(map, _env) when is_map(map) do
    Map.keys(map)
  end

  def flatten(list, _env) when is_list(list) do
    List.flatten(list)
  end

  def map(enumerable, {:lambda_fn, _args, _body} = lambda_fn, %Environment{} = env) do
    reduce(enumerable, lambda_fn, env)
    |> Enum.reverse()
  end

  def filter(enumerable, {:lambda_fn, _args, _body} = lambda_fn, %Environment{} = env) do
    {:lambda_fn, [{:identifier, _, local_binding}], _body} = lambda_fn

    enumerable
    |> Enum.reduce({[], env}, fn elem, {acc, env} ->
      env = Environment.add_local_binding(env, local_binding, elem)

      case Interpreter.eval(lambda_fn, env) do
        falsey when falsey in [false, nil] ->
          {acc, env}

        _ ->
          {[elem | acc], env}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  def flat_map(enumerable, {:lambda_fn, _args, _body} = lambda_fn, %Environment{} = env) do
    reduce(enumerable, lambda_fn, env)
    |> flat_reverse([])
  end

  # Private functions

  defp flat_reverse([h | t], acc), do: flat_reverse(t, h ++ acc)
  defp flat_reverse([], acc), do: acc

  defp reduce(enumerable, lambda_fn, env) do
    {:lambda_fn, [{:identifier, _, local_binding}], _body} = lambda_fn

    enumerable
    |> Enum.reduce({[], env}, fn elem, {acc, env} ->
      env = Environment.add_local_binding(env, local_binding, elem)

      computed_item = Interpreter.eval(lambda_fn, env)
      {[computed_item | acc], env}
    end)
    |> elem(0)
  end
end
