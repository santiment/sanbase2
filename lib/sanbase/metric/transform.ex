defmodule Sanbase.Metric.Transform do
  @moduledoc false
  def transform_to_value_pairs(data, key_name \\ nil)

  def transform_to_value_pairs({:ok, []}, _), do: {:ok, []}

  def transform_to_value_pairs({:ok, result}, nil) do
    # deduce the key name. It is the key other than the :datetime
    # If there are more than 1 key different than :datetime then this will
    # fail. In such cases an explicit key name should be passed
    [key_name] = (result |> hd() |> Map.keys()) -- [:datetime]

    result =
      Enum.map(result, fn %{^key_name => value, datetime: datetime} ->
        %{value: value, datetime: datetime}
      end)

    {:ok, result}
  end

  def transform_to_value_pairs({:ok, result}, key_name) do
    result =
      Enum.map(result, fn %{^key_name => value, datetime: datetime} ->
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

  def exec_timeseries_data_query(%Sanbase.Clickhouse.Query{} = query) do
    Sanbase.ClickhouseRepo.query_transform(query, fn
      [unix, value] ->
        %{datetime: DateTime.from_unix!(unix), value: value}

      [unix, open, high, low, close] ->
        %{
          datetime: DateTime.from_unix!(unix),
          value_ohlc: %{
            open: open,
            high: high,
            low: low,
            close: close
          }
        }
    end)
  end
end
