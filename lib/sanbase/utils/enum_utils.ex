defmodule Sanbase.EnumUtils do
  @moduledoc false
  @doc ~s"""
  Execute Enum.reduce/3 over the enumerable, choosing which function to execute
  based on `limit`. Execute `success_fun` at most `limit` number of times. In the
  rest of the cases execute `limit_fun`
  """
  def reduce_limited_times(enumerable, limit, success_fun, limit_fun, opts \\ []) do
    acc = Keyword.get(opts, :accumulator, [])

    {result, remaining_limit} =
      Enum.reduce(enumerable, {acc, limit}, fn elem, {acc, remaining} ->
        case remaining do
          0 ->
            acc = limit_fun.(elem, acc)

            {acc, 0}

          _ ->
            acc = success_fun.(elem, acc)
            {acc, remaining - 1}
        end
      end)

    {:ok, %{result: result, remaining_limit: remaining_limit}}
  end
end
