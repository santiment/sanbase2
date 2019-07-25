defmodule Sanbase.Signal.Operation do
  @spec type(map()) :: :percent | :absolute
  def type(operation) when is_map(operation) do
    has_percent? =
      Enum.any?(Map.keys(operation), fn name ->
        name |> Atom.to_string() |> String.contains?("percent")
      end)

    if has_percent? do
      :percent
    else
      :absolute
    end
  end
end
