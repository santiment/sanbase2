defmodule SanbaseWeb.Graphql.InfluxdbDataloader do
  alias Sanbase.Prices
  alias SanbaseWeb.Graphql.Helpers.{Cache, Utils}

  def data() do
    Dataloader.KV.new(&query/2)
  end

  def query(:volume_change_24h, args) do
    measurements = args |> Enum.map(&Sanbase.Influxdb.Measurement.name_from/1)

    now = Timex.now()
    yesterday = Timex.shift(now, days: -1)
    two_days_ago = Timex.shift(now, days: -2)

    measurements
    |> Enum.chunk_every(200)
    |> Sanbase.Parallel.pmap(fn measurements ->
      volumes_last_24h = Prices.Store.fetch_mean_volume(measurements, yesterday, now)

      volumes_previous_24h_map =
        Prices.Store.fetch_mean_volume(measurements, two_days_ago, yesterday) |> Map.new()

      volumes_last_24h
      |> Enum.map(fn {name, today_vol} ->
        yesterday_vol = Map.get(volumes_previous_24h_map, name, 0)

        if yesterday_vol > 1 do
          {name, (today_vol - yesterday_vol) * 100 / yesterday_vol}
        end
      end)
      |> Enum.reject(&is_nil/1)
    end)
    |> Enum.flat_map(& &1)
    |> Map.new()
  end

  def query(measurement, ids) do
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
