defmodule Sanbase.ExternalServices.Coinmarketcap.PricePoint do
  alias __MODULE__
  alias Sanbase.Influxdb.Measurement

  defstruct [:datetime, :marketcap, :price_usd, :volume_usd, :price_btc, :volume_btc]

  def convert_to_measurement(%PricePoint{datetime: datetime} = point, suffix, name) do
    %Measurement{
      timestamp: DateTime.to_unix(datetime, :nanosecond),
      fields: price_point_to_fields(point, suffix),
      tags: [],
      name: name <> "_#{suffix}"
    }
  end

  defp price_point_to_fields(
         %PricePoint{marketcap: marketcap, volume_usd: volume_usd, price_btc: price_btc},
         "BTC"
       ) do
    %{
      price: price_btc,
      volume: volume_usd,
      marketcap: marketcap
    }
  end

  defp price_point_to_fields(
         %PricePoint{marketcap: marketcap, volume_usd: volume_usd, price_usd: price_usd},
         "USD"
       ) do
    %{
      price: price_usd,
      volume: volume_usd,
      marketcap: marketcap
    }
  end
end
