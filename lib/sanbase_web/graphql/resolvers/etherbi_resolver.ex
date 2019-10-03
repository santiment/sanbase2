defmodule SanbaseWeb.Graphql.Resolvers.EtherbiResolver do
  require Logger

  import SanbaseWeb.Graphql.Helpers.Utils, only: [fit_from_datetime: 2, calibrate_interval: 7]
  import Sanbase.Utils.ErrorHandling, only: [handle_graphql_error: 3]

  alias Sanbase.Model.{Infrastructure, Project, ExchangeAddress}

  alias Sanbase.Blockchain.TokenAgeConsumed

  # Return this number of datapoints is the provided interval is an empty string
  @datapoints 50

  @doc ~S"""
  Return the token age consumed for the given slug and time period.
  """
  def token_age_consumed(
        _root,
        %{slug: _slug, from: _from, to: _to, interval: _interval} = args,
        _resolution
      ) do
    SanbaseWeb.Graphql.Resolvers.MetricResolver.get_timeseries_data(
      %{},
      args,
      %{source: %{metric: "age_destroyed"}}
    )
    |> Sanbase.Utils.Transform.duplicate_map_keys(:value, :burn_rate)
    |> Sanbase.Utils.Transform.rename_map_keys(:value, :token_age_consumed)
  end

  @doc ~S"""
  Return the average age of the tokens that were transacted for the given slug and time period.
  """
  def average_token_age_consumed_in_days(
        _root,
        %{slug: slug, from: from, to: to, interval: interval} = args,
        _resolution
      ) do
    with {:ok, contract, token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           calibrate_interval(TokenAgeConsumed, contract, from, to, interval, 3600, @datapoints),
         {:ok, token_age} <-
           TokenAgeConsumed.average_token_age_consumed_in_days(
             contract,
             from,
             to,
             interval,
             token_decimals
           ) do
      {:ok, token_age |> fit_from_datetime(args)}
    else
      {:error, error} ->
        {:error, handle_graphql_error("Average Token Age Consumed In Days", slug, error)}
    end
  end

  def transaction_volume(
        _root,
        %{slug: _slug, from: _from, to: _to, interval: _interval} = args,
        _resolution
      ) do
    SanbaseWeb.Graphql.Resolvers.MetricResolver.get_timeseries_data(
      %{},
      args,
      %{source: %{metric: "transaction_volume"}}
    )
    |> Sanbase.Utils.Transform.rename_map_keys(:value, :transaction_volume)
  end

  @doc ~S"""
  Return the amount of tokens that were transacted in or out of an exchange wallet for a given slug
  and time period
  """
  def exchange_funds_flow(
        _root,
        %{slug: _slug, from: _from, to: _to, interval: _interval} = args,
        _resolution
      ) do
    SanbaseWeb.Graphql.Resolvers.MetricResolver.get_timeseries_data(
      %{},
      args,
      %{source: %{metric: "exchange_balance"}}
    )
    |> Sanbase.Utils.Transform.rename_map_keys(:value, :in_out_difference)
  end

  def token_velocity(
        _root,
        %{slug: _slug, from: _from, to: _to, interval: _interval} = args,
        _resolution
      ) do
    SanbaseWeb.Graphql.Resolvers.MetricResolver.get_timeseries_data(
      %{},
      args,
      %{source: %{metric: "velocity"}}
    )
    |> Sanbase.Utils.Transform.rename_map_keys(:value, :token_velocity)
  end

  def all_exchange_wallets(_root, _args, _resolution) do
    {:ok, ExchangeAddress.all_exchange_wallets()}
  end

  def exchange_wallets(_root, %{slug: "ethereum"}, _resolution) do
    {:ok, ExchangeAddress.exchange_wallets_by_infrastructure(Infrastructure.get("ETH"))}
  end

  def exchange_wallets(_root, %{slug: "bitcoin"}, _resolution) do
    {:ok, ExchangeAddress.exchange_wallets_by_infrastructure(Infrastructure.get("BTC"))}
  end

  def exchange_wallets(_, _, _) do
    {:error, "Currently only ethereum and bitcoin exchanges are supported"}
  end
end
