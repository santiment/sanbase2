defmodule Sanbase.ExternalServices.Coinmarketcap.PricePoint do
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Model.Project

  @prices_source "coinmarketcap"
  defstruct [
    :ticker,
    :slug,
    :datetime,
    :marketcap_usd,
    :volume_usd,
    :price_usd,
    :price_btc
  ]

  def json_kv_tuple(%__MODULE__{datetime: datetime} = point, slug, source \\ @prices_source) do
    key = source <> "_" <> slug <> "_" <> DateTime.to_iso8601(datetime)

    value =
      %{
        timestamp: DateTime.to_unix(datetime),
        source: source,
        slug: slug
      }
      |> Map.merge(price_point_fields(point))
      |> Jason.encode!()

    {key, value}
  end

  def convert_to_measurement(%__MODULE__{datetime: datetime} = point, name) do
    %Measurement{
      timestamp: DateTime.to_unix(datetime, :nanosecond),
      fields: price_point_fields(point),
      tags: [],
      name: name
    }
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

  def price_points_to_measurements(price_points, measurement) when is_binary(measurement) do
    price_points
    |> List.wrap()
    |> Enum.map(fn price_point ->
      convert_to_measurement(price_point, measurement)
    end)
  end

  def price_points_to_measurements(_, _), do: []

  # Private functions

  defp price_point_fields(%__MODULE__{
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
