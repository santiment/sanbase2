defmodule Sanbase.InfluxdbHelpers do
  defmacro setup_twitter_influxdb() do
    quote do
      Sanbase.Twitter.Store.create_db()

      on_exit(fn ->
        Sanbase.Twitter.Store.drop_db()
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
