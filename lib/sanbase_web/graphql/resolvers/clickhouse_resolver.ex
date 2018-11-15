defmodule SanbaseWeb.Graphql.Resolvers.ClickhouseResolver do
  require Logger

  alias Sanbase.DateTimeUtils
  alias Sanbase.Clickhouse.EthTransfers

  @one_hour_seconds 3600

  def historical_balance(
        _root,
        %{address: address, from: from, to: to, interval: interval},
        _resolution
      ) do
    calc_historical_balances(address, from, to, interval)
  end

  defp calc_historical_balances(address, from, to, interval) do
    with interval_seconds when interval_seconds >= @one_hour_seconds <-
           DateTimeUtils.compound_duration_to_seconds(interval),
         {:ok, result} <- EthTransfers.historical_balance(address, from, to, interval_seconds) do
      {:ok, result}
    else
      e when is_integer(e) ->
        {:error, "Interval must be bigger than 1 hour"}

      error ->
        Logger.warn(
          "Cannot calculate historical balances for #{address}. Reason: #{inspect(error)}"
        )

        {:ok, []}
    end
  rescue
    e ->
      Logger.error(
        "Exception raised while calculating historical balances for #{address}. Reason: #{
          inspect(e)
        }"
      )

      {:ok, []}
  end
end
