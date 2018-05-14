defmodule SanbaseWeb.Graphql.PriceStore do
  alias Sanbase.Prices
  alias SanbaseWeb.Graphql.Helpers.Cache

  def data() do
    Dataloader.KV.new(&query/2)
  end

  def query(measurement, ids) when is_list(ids) do
    ids
    |> Enum.uniq()
    |> Enum.map(fn id ->
      {id, fetch_price(measurement, id)}
    end)
    |> Map.new()
  end

  # Helper functions

  # TODO: not covered in tests
  defp fetch_price(measurement, :last) do
    Cache.func(fn -> fetch_last_price_record(measurement) end, :fetch_price_last_record, %{
      measurement: measurement
    }).()
  end

  defp fetch_price(measurement, %{from: from, to: to, interval: interval} = args) do
    Cache.func(
      fn ->
        Prices.Store.fetch_prices_with_resolution(measurement, from, to, interval)
      end,
      :fetch_prices_with_resolution,
      Map.merge(%{measurement: measurement}, args)
    ).()
  end

  defp fetch_last_price_record(measurement) do
    with {:ok, [[_dt, price_usd, price_btc, _mcap, _volume]]} <-
           Prices.Store.last_record(measurement) do
      {price_usd, price_btc}
    else
      _error -> {nil, nil}
    end
  end
end
