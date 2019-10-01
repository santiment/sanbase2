defmodule Sanbase.Metric.Helper do
  def transform_to_value_pairs({:ok, result}, key_name) do
    result =
      result
      |> Enum.map(fn %{^key_name => value, datetime: datetime} ->
        %{value: value, datetime: datetime}
      end)

    {:ok, result}
  end

  def transform_to_value_pairs({:error, error}, _), do: {:error, error}
end
