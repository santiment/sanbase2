defmodule Sanbase.ExternalServices.Coinbase.GraphData do
  defstruct [:market_cap_by_available_supply, :price_usd, :volume_usd]

  alias Sanbase.ExternalServices.Coinbase.GraphData
  alias Sanbase.Prices.Point

  def parse_json(json) do
    json
    |> Poison.decode!(as: %GraphData{})
    |> convert_to_price_points
  end

  defp convert_to_price_points(%GraphData{
    market_cap_by_available_supply: market_cap_by_available_supply,
    price_usd: price_usd,
    volume_usd: volume_usd
  }) do
    List.zip([market_cap_by_available_supply, price_usd, volume_usd])
    |> Enum.map(fn {[dt, marketcap], [dt, price], [dt, volume]} ->
      %Point{marketcap: marketcap, price: price, volume: volume, datetime: DateTime.from_unix!(dt, :millisecond)}
    end)
  end
end
