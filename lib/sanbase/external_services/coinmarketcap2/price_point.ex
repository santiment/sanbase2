defmodule Sanbase.ExternalServices.Coinmarketcap.PricePoint2 do
  # TODO: Change after switching over to only this cmc
  alias __MODULE__, as: PricePoint
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Model.Project

  defstruct [
    :ticker,
    :slug,
    :datetime,
    :marketcap_usd,
    :volume_usd,
    :price_usd,
    :price_btc
  ]

  def convert_to_measurement(%PricePoint{datetime: datetime} = point, name) do
    %Measurement{
      timestamp: DateTime.to_unix(datetime, :nanosecond),
      fields: price_point_fields(point),
      tags: [],
      name: name
    }
  end

  def price_points_to_measurements(price_points, "TOTAL_MARKET_total-market" = total_market) do
    price_points
    |> List.wrap()
    |> Enum.map(fn price_point ->
      convert_to_measurement(price_point, total_market)
    end)
  end

  def price_points_to_measurements(
        price_points,
        %Project{} = project
      ) do
    price_points
    |> List.wrap()
    |> Enum.map(fn price_point ->
      convert_to_measurement(price_point, Measurement.name_from(project))
    end)
  end

  def price_points_to_measurements(_, _), do: []

  # Private functions

  defp price_point_fields(%PricePoint{
         marketcap_usd: marketcap_usd,
         volume_usd: volume_usd,
         price_btc: price_btc,
         price_usd: price_usd
       }) do
    %{
      price_usd: price_usd,
      price_btc: price_btc,
      volume_usd: volume_usd,
      marketcap_usd: marketcap_usd
    }
  end
end
