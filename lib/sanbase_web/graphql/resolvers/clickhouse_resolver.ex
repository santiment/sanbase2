defmodule SanbaseWeb.Graphql.Resolvers.ClickhouseResolver do
  require Logger

  alias Sanbase.Model.Project
  alias Sanbase.DateTimeUtils
  alias SanbaseWeb.Graphql.Helpers.Utils
  alias Sanbase.Clickhouse.{HistoricalBalance, MVRV, NetworkGrowth}

  def network_growth(_root, args, _resolution) do
    interval = DateTimeUtils.compound_duration_to_seconds(args.interval)

    with {:ok, contract, _} <- Project.contract_info_by_slug(args.slug),
         {:ok, network_growth} <-
           NetworkGrowth.network_growth(contract, args.from, args.to, interval) do
      {:ok, network_growth}
    else
      error ->
        Logger.error("Can't calculate network growth. Reason: #{inspect(error)}")

        {:error, "Can't calculate network growth"}
    end
  end

  def mvrv_ratio(_root, args, _resolution) do
    # TODO: Check if interval is a whole day as in token circulation
    with {:ok, mvrv_ratio} <- MVRV.mvrv_ratio(args.slug, args.from, args.to, args.interval) do
      {:ok, mvrv_ratio}
    else
      {:error, error} ->
        error_message = Utils.build_error_message("MVRV ratio", args.slug)
        Utils.log_error(error, error_message)

        {:error, error_message}
    end
  end

  def historical_balance(
        _root,
        %{slug: slug, from: from, to: to, interval: interval, address: address},
        _resolution
      ) do
    with {:ok, result} <- HistoricalBalance.historical_balance(address, slug, from, to, interval) do
      {:ok, result}
    else
      {:error, error} ->
        Logger.warn(
          "Can't calculate historical balances for project with coinmarketcap_id #{slug}. Reason: #{
            inspect(error)
          }"
        )

        {:error, "Can't calculate historical balances for project with coinmarketcap_id #{slug}"}
    end
  end
end
