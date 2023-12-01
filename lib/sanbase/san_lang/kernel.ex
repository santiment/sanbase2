defmodule Sanbase.SanLang.Kernel do
  alias Sanbase.SanLang.Environment
  alias Sanbase.SanLang.Interpreter

  def pow(base, pow) when is_number(base) and is_number(pow) do
    base ** pow
  end

  def map(
        enumerable,
        {:lambda_fn, [{:identifier, _, local_binding}], _body} = fun,
        %Environment{} = env
      ) do
    enumerable
    |> Enum.reduce({[], env}, fn elem, {acc, env} ->
      env = Environment.add_local_binding(env, local_binding, elem)

      computed_item = Interpreter.true_eval_lambda_fn(fun, env)
      {[computed_item | acc], env}
    end)
    |> elem(0)
    |> Enum.reverse()
  end
end
