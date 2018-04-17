defmodule Sanbase.ExternalServices.Coinmarketcap.PricePoint do
  alias __MODULE__
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Model.Project

  defstruct [:datetime, :marketcap, :price_usd, :volume_usd, :price_btc, :volume_btc]

  def convert_to_measurement(%PricePoint{datetime: datetime} = point, suffix, name) do
    %Measurement{
      timestamp: DateTime.to_unix(datetime, :nanosecond),
      fields: price_point_to_fields(point, suffix),
      tags: [],
      name: name <> "_#{suffix}"
    }
  end

  def price_points_to_measurements(%PricePoint{} = price_point) do
    [convert_to_measurement(price_point, "USD", "TOTAL_MARKET")]
  end

  def price_points_to_measurements(price_points) do
    price_points
    |> Enum.flat_map(fn price_point ->
      [convert_to_measurement(price_point, "USD", "TOTAL_MARKET")]
    end)
  end

  def price_points_to_measurements(%PricePoint{} = price_point, %Project{ticker: ticker}) do
    [
      convert_to_measurement(price_point, "USD", ticker),
      convert_to_measurement(price_point, "BTC", ticker)
    ]
  end

  def price_points_to_measurements(price_points, %Project{ticker: ticker}) do
    price_points
    |> Enum.flat_map(fn price_point ->
      [
        convert_to_measurement(price_point, "USD", ticker),
        convert_to_measurement(price_point, "BTC", ticker)
      ]
    end)
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
