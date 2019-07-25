defmodule Sanbase.InfluxdbHelpers do
  defmacro setup_twitter_influxdb() do
    quote do
      Sanbase.ExternalServices.TwitterData.Store.create_db()

      on_exit(fn ->
        Sanbase.ExternalServices.TwitterData.Store.drop_db()
      end)
    end
  end

  defmacro setup_prices_influxdb() do
    quote do
      Sanbase.Prices.Store.create_db()

      on_exit(fn ->
        Sanbase.Prices.Store.drop_db()
      end)
    end
  end
end
