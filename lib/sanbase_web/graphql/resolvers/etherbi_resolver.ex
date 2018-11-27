defmodule SanbaseWeb.Graphql.Resolvers.EtherbiResolver do
  alias Sanbase.Repo
  alias Sanbase.Model.{Project, ExchangeAddress}
  alias SanbaseWeb.Graphql.Helpers.{Cache, Utils}

  alias Sanbase.Blockchain

  import SanbaseWeb.Graphql.Helpers.Async
  import Ecto.Query

  require Logger

  def burn_rate(_root, %{slug: slug} = args, _resolution) do
    with {:ok, contract_address, token_decimals} <- Project.contract_info_by_slug(slug) do
      Cache.func(
        fn -> calculate_burn_rate(contract_address, token_decimals, args) end,
        {:burn_rate, contract_address},
        %{from_datetime: args.from, to_datetime: args.to}
      ).()
    end
  end

  defp calculate_burn_rate(contract_address, token_decimals, args) do
    %{from: from, to: to, interval: interval, slug: slug} = args

    with {:ok, from, to, interval} <-
           Utils.calibrate_interval(
             Blockchain.BurnRate,
             contract_address,
             from,
             to,
             interval,
             60 * 60,
             50
           ),
         {:ok, burn_rates} <-
           Blockchain.BurnRate.burn_rate(
             contract_address,
             from,
             to,
             interval,
             token_decimals
           ) do
      result =
        burn_rates
        |> Utils.fit_from_datetime(args)

      {:ok, result}
    else
      error ->
        error_msg = "Can't fetch burn rate for #{slug}"
        Logger.warn(error_msg <> "Reason: #{inspect(error)}")
        {:error, error_msg}
    end
  end

  def transaction_volume(_root, %{slug: slug} = args, _resolution) do
    with {:ok, contract_address, token_decimals} <- Project.contract_info_by_slug(slug) do
      Cache.func(
        fn -> calculate_transaction_volume(contract_address, token_decimals, args) end,
        {:transaction_volume, contract_address},
        %{from_datetime: args.from, to_datetime: args.to}
      ).()
    end
  end

  defp calculate_transaction_volume(contract_address, token_decimals, args) do
    %{from: from, to: to, interval: interval, slug: slug} = args

    with {:ok, from, to, interval} <-
           Utils.calibrate_interval(
             Blockchain.TransactionVolume,
             contract_address,
             from,
             to,
             interval,
             60 * 60,
             50
           ),
         {:ok, trx_volumes} <-
           Blockchain.TransactionVolume.transaction_volume(
             contract_address,
             from,
             to,
             interval,
             token_decimals
           ) do
      result =
        trx_volumes
        |> Utils.fit_from_datetime(args)

      {:ok, result}
    else
      error ->
        error_msg = "Can't fetch transaction for #{slug}"
        Logger.warn(error_msg <> "Reason: #{inspect(error)}")
        {:error, error_msg}
    end
  end

  def token_age_consumed_in_days(
        root,
        %{slug: slug, from: from, to: to, interval: interval} = args,
        resolution
      ) do
    with {:ok, burn_rates} <- burn_rate(root, args, resolution),
         {:ok, transaction_volumes} <- transaction_volume(root, args, resolution) do
      result =
        Enum.zip(burn_rates, transaction_volumes)
        |> Enum.map(fn {%{datetime: dt, burn_rate: burn_rate},
                        %{datetime: dt, transaction_volume: transaction_volume}} ->
          token_age =
            case transaction_volume do
              0.0 -> 0
              _ -> burn_rate / transaction_volume * 15 / 86400
            end

          %{
            datetime: dt,
            token_age: token_age
          }
        end)

      {:ok, result}
    else
      error ->
        error_msg = "Can't fetch token age for #{slug}"
        Logger.warn(error_msg <> "Reason: #{inspect(error)}")
        {:error, error_msg}
    end
  end

  def token_circulation(
        _root,
        %{slug: slug, from: from, to: to, interval: interval} = args,
        _resolution
      ) do
    with {:ok, contract_address, token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           Utils.calibrate_interval(
             Blockchain.TokenCirculation,
             contract_address,
             from,
             to,
             interval,
             60 * 60,
             50
           ),
         {:ok, token_circulation} <-
           Blockchain.TokenCirculation.token_circulation(
             :less_than_a_day,
             contract_address,
             from,
             to,
             interval,
             token_decimals
           ) do
      result =
        token_circulation
        |> Utils.fit_from_datetime(args)

      {:ok, result}
    else
      error ->
        error_msg = "Can't fetch token circulation for #{slug}"
        Logger.warn(error_msg <> "Reason: #{inspect(error)}")
        {:error, error_msg}
    end
  end

  @doc ~S"""
    Return the number of daily active addresses for a given slug
  """
  def daily_active_addresses(
        _root,
        %{slug: slug, from: from, to: to, interval: interval} = args,
        _resolution
      ) do
    with {:ok, contract_address, _token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           Utils.calibrate_interval(
             Blockchain.DailyActiveAddresses,
             contract_address,
             from,
             to,
             interval,
             24 * 60 * 60,
             50
           ),
         {:ok, daily_active_addresses} <-
           Blockchain.DailyActiveAddresses.active_addresses(
             contract_address,
             from,
             to,
             interval
           ) do
      result =
        daily_active_addresses
        |> Utils.fit_from_datetime(args)

      {:ok, result}
    else
      error ->
        error_msg = "Can't fetch daily active addresses for #{slug}"
        Logger.warn(error_msg <> "Reason: #{inspect(error)}")
        {:error, error_msg}
    end
  end

  @doc ~S"""
    Return the transactions that happend in or out of an exchange wallet for a given slug
    and time period.
    Uses the influxdb cached values instead of issuing a GET request to etherbi
  """
  def exchange_funds_flow(
        _root,
        %{
          slug: slug,
          from: from,
          to: to,
          interval: interval
        } = args,
        _resolution
      ) do
    with {:ok, contract_address, token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           Utils.calibrate_interval(
             Blockchain.ExchangeFundsFlow,
             contract_address,
             from,
             to,
             interval,
             60 * 60
           ),
         {:ok, exchange_funds_flow} <-
           Blockchain.ExchangeFundsFlow.transactions_in_out_difference(
             contract_address,
             from,
             to,
             interval,
             token_decimals
           ) do
      result =
        exchange_funds_flow
        |> Utils.fit_from_datetime(args)

      {:ok, result}
    else
      error ->
        error_msg = "Can't fetch the exchange fund flow for #{slug}."
        Logger.warn(error_msg <> "Reason: #{inspect(error)}")
        {:error, error_msg}
    end
  end

  def exchange_wallets(_root, _args, _resolution) do
    {:ok, ExchangeAddress |> Repo.all()}
  end

  @doc ~S"""
    Return the average number of daily active addresses for a given slug and period of time
  """
  def average_daily_active_addresses(
        %Project{id: id} = project,
        %{from: from, to: to} = args,
        _resolution
      ) do
    async(
      Cache.func(
        fn -> calculate_average_daily_active_addresses(project, from, to) end,
        {:average_daily_active_addresses, id},
        args
      )
    )
  end

  def average_daily_active_addresses(
        %Project{id: id} = project,
        _args,
        _resolution
      ) do
    month_ago = Timex.shift(Timex.now(), days: -30)

    async(
      Cache.func(
        fn -> calculate_average_daily_active_addresses(project, month_ago, Timex.now()) end,
        {:average_daily_active_addresses, id}
      )
    )
  end

  def calculate_average_daily_active_addresses(project, from, to) do
    with {:ok, contract_address, _token_decimals} <- Project.contract_info(project),
         {:ok, active_addresses} <-
           Blockchain.DailyActiveAddresses.active_addresses(contract_address, from, to) do
      {:ok, active_addresses}
    else
      error ->
        error_msg = "Can't fetch daily active addresses for #{project.coinmarketcap_id}"
        Logger.warn(error_msg <> "Reason: #{inspect(error)}")

        {:ok, 0}
    end
  end
end
