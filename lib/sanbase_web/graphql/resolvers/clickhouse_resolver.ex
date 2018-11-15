defmodule SanbaseWeb.Graphql.Resolvers.ClickhouseResolver do
  require Logger

  def historical_balance(
    _root,
    %{address: address, from: from, to: to, interval: interval},
    _resolution) do
    interval = Sanbase.DateTimeUtils.compound_duration_to_seconds(interval)
    result = Sanbase.Clickhouse.EthTransfers.historical_balance(
      address, from, to, interval
    )
    {:ok, result}
  end
end
