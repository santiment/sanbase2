defmodule Sanbase.Utils.Transform do
  def rename_map_keys({:ok, data}, old_key, new_key) do
    result =
      data
      |> Enum.map(fn %{^old_key => value} = elem ->
        elem |> Map.delete(old_key) |> Map.put(new_key, value)
      end)

    {:ok, result}
  end

  def rename_map_keys({:error, error}, _, _) do
    {:error, error}
  end
end
