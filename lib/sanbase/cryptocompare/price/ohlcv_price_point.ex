defmodule Sanbase.Cryptocompare.OHLCVPricePoint do
  @moduledoc false
  defstruct [
    :base_asset,
    :quote_asset,
    :datetime,
    :open,
    :high,
    :close,
    :low,
    :volume_from,
    :volume_to,
    :source,
    :interval_seconds
  ]

  def new(map) when is_map(map) do
    %__MODULE__{
      base_asset: map.base_asset,
      quote_asset: map.quote_asset,
      datetime: map.datetime,
      open: map.open,
      high: map.high,
      close: map.close,
      low: map.low,
      volume_from: map.volume_from,
      volume_to: map.volume_to,
      source: map.source,
      interval_seconds: map.interval_seconds
    }
  end

  def json_kv_tuple(%__MODULE__{} = point) do
    point =
      point
      |> Map.put(:timestamp, DateTime.to_unix(point.datetime))
      |> Map.delete(:datetime)
      |> Map.from_struct()

    key = Enum.join([point.source, point.base_asset, point.quote_asset, point.timestamp], "_")

    {key, Jason.encode!(point)}
  end
end
