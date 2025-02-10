defmodule Sanbase.Cryptocompare.PriceOnlyPoint do
  @moduledoc false
  defstruct [
    :base_asset,
    :quote_asset,
    :datetime,
    :price,
    :source
  ]

  def new(map) when is_map(map) do
    %__MODULE__{
      base_asset: map.base_asset,
      quote_asset: map.quote_asset,
      datetime: map.datetime,
      price: map.price,
      source: map.source
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
