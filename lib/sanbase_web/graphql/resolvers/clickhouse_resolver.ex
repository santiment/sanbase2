defmodule SanbaseWeb.Graphql.Resolvers.ClickhouseResolver do
  require Logger

  alias Sanbase.DateTimeUtils
  alias Sanbase.Clickhouse.EthTransfers
  alias Sanbase.Clickhouse.Erc20Transfers
  alias Sanbase.Model.Project

  alias Sanbase.Clickhouse.NetworkGrowth

  @one_hour_seconds 3600

  def network_growth(_root, args, _resolution) do
    with {:ok, contract, _} <- args.slug |> Project.by_slug() |> Project.contract_info(),
         interval <- DateTimeUtils.compound_duration_to_seconds(args.interval),
         {:ok, network_growth} =
           NetworkGrowth.network_growth(contract, args.from, args.to, interval) do
      {:ok, network_growth}
    else
      error ->
        Logger.warn("Can't calculate network growth. Reason: #{inspect(error)}")

        {:ok, []}
    end
  rescue
    e ->
      Logger.error("Exception raised while calculating network growth. Reason: #{inspect(e)}")

      {:ok, []}
  end

  def historical_balance(
        _root,
        args,
        _resolution
      ) do
    with interval_seconds when interval_seconds >= @one_hour_seconds <-
           DateTimeUtils.compound_duration_to_seconds(args.interval),
         {:ok, result} <- calc_historical_balances(args, interval_seconds) do
      {:ok, result}
    else
      e when is_integer(e) ->
        {:error, "Interval must be bigger than 1 hour"}

      error ->
        Logger.warn("Can't calculate historical balances. Reason: #{inspect(error)}")

        {:ok, []}
    end
  rescue
    e ->
      Logger.error(
        "Exception raised while calculating historical balances. Reason: #{inspect(e)}"
      )

      {:ok, []}
  end

  defp calc_historical_balances(
         %{slug: slug, address: address, from: from, to: to},
         interval_seconds
       ) do
    with {:ok, contract, token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, result} <-
           Erc20Transfers.historical_balance(
             contract,
             address,
             from,
             to,
             interval_seconds,
             token_decimals
           ) do
      {:ok, result}
    else
      {:error, error} -> {:error, error}
    end
  end

  defp calc_historical_balances(%{address: address, from: from, to: to}, interval_seconds) do
    EthTransfers.historical_balance(address, from, to, interval_seconds)
  end
end
