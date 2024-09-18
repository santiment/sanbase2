defmodule Sanbase.SanLang.Kernel do
  alias Sanbase.SanLang.Environment
  alias Sanbase.SanLang.Interpreter
  alias Sanbase.SanLang.FunctionArgumentError

  def pow(base, pow, _env) when is_number(base) and is_number(pow) do
    base ** pow
  end

  def div(dividend, divisor, _env) when is_number(dividend) and is_number(divisor) do
    div(dividend, divisor)
  end

  def length(list, _env) when is_list(list), do: length(list)

  def load(path, _env) do
    with {:ok, struct} <- Sanbase.Queries.ExternalData.resolve_path(path),
         {:ok, data} <- Sanbase.Queries.ExternalData.get(struct) do
      data
    else
      {:error, error} ->
        error_msg = "Failed evaluation: load(#{inspect(path)}). Reason: #{error}"
        raise(FunctionArgumentError, error_msg)
    end
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
    # This is because at the moment we support only 1-arity anonymous
    # functions. This next line is basically getting the function argument
    {:lambda_fn, [{:identifier, _, local_binding}], _body} = lambda_fn

    enumerable
    |> Enum.reduce({[], env}, fn elem, {acc, env} ->
      # Add to the environment the value of the current element that is being
      # reduced, using the argument name, so when the body refers to it, its
      # value is retrieved
      env = Environment.add_local_binding(env, local_binding, elem)

      computed_item = Interpreter.eval(lambda_fn, env)
      {[computed_item | acc], env}
    end)
    |> elem(0)
  end
end
