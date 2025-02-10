defmodule Sanbase.Cryptocompare.PricePoint do
  @moduledoc false
  defstruct [
    :base_asset,
    :quote_asset,
    :datetime,
    :price,
    :volume_24h,
    :volume_24h_to,
    :top_tier_volume_24h,
    :top_tier_volume_24h_to,
    :volume_day,
    :volume_day_to,
    :volume_hour,
    :volume_hour_to,
    :source
  ]

  def new(map) when is_map(map) do
    %__MODULE__{
      base_asset: map.base_asset,
      quote_asset: map.quote_asset,
      datetime: map.datetime,
      price: map.price,
      volume_24h: map.volume_24h,
      volume_24h_to: map.volume_24h_to,
      top_tier_volume_24h: map.top_tier_volume_24h,
      top_tier_volume_24h_to: map.top_tier_volume_24h_to,
      volume_day: map.volume_day,
      volume_day_to: map.volume_day_to,
      volume_hour: map.volume_hour,
      volume_hour_to: map.volume_hour_to,
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
