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

  @doc ~s"""
  Replace all values except :slug and :datetime in every element with `nil`
  if :has_changed is 0
  """
  def maybe_nullify_values({:ok, data}) do
    result =
      Enum.map(
        data,
        fn
          %{has_changed: 0} = elem ->
            # use :maps.map/2 instead of Enum.map/2 to avoid unnecessary Map.new/1
            :maps.map(
              fn
                key, value when key in [:slug, :datetime] -> value
                _, _ -> nil
              end,
              Map.delete(elem, :has_changed)
            )

          elem ->
            Map.delete(elem, :has_changed)
        end
      )

    {:ok, result}
  end

  def maybe_nullify_values({:error, error}), do: {:error, error}

  @doc ~s"""
  Remove all elements for which :has_changed is 0
  """
  def remove_missing_values({:ok, data}) do
    {:ok, Enum.reject(data, &(&1.has_changed == 0))}
  end

  def remove_missing_values({:error, error}), do: {:error, error}
end
