defmodule Sanbase.InfluxdbHelpers do
  defmacro setup_twitter_influxdb() do
    quote do
      Sanbase.Twitter.Store.create_db()

      on_exit(fn ->
        Sanbase.Twitter.Store.drop_db()
      end)
    end
  end
end
