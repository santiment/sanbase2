defmodule SanbaseWeb.Graphql.PriceStore do
  alias Sanbase.Prices
  alias SanbaseWeb.Graphql.Helpers.{Cache, Utils}

  def data() do
    Dataloader.KV.new(&query/2)
  end

  def query(measurement, ids) do
    ids
    |> Enum.uniq()
    |> Enum.map(fn id ->
      {id, fetch_price(measurement, id)}
    end)
    |> Map.new()
  end

  def query(queryable, _), do: queryable

  # Helper functions

  # TODO: not covered in tests
  defp fetch_price(measurement, :last) do
    Cache.func(
      fn -> fetch_last_price_record(measurement) end,
      :fetch_price_last_record,
      %{measurement: measurement}
    ).()
  end

  defp fetch_price(measurement, %{from: from, to: to, interval: interval} = args) do
    {:ok, from, to, interval} =
      Utils.calibrate_interval(Prices.Store, measurement, from, to, interval, 60)

    Cache.func(
      fn ->
        Prices.Store.fetch_prices_with_resolution(measurement, from, to, interval)
      end,
      :fetch_prices_with_resolution,
      Map.merge(%{measurement: measurement}, args)
    ).()
  end

  defp fetch_last_price_record(measurement) do
    with {:ok, [[_dt, _mcap, price_btc, price_usd, _volume]]} <-
           Prices.Store.last_record(measurement) do
      {price_usd, price_btc}
    else
      _error -> {nil, nil}
    end
  end
end
