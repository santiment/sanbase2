defmodule SanbaseWeb.Graphql.Resolvers.EtherbiResolver do
  require Logger

  alias Sanbase.Model.{Infrastructure, ExchangeAddress}

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
    |> Sanbase.Utils.Transform.rename_map_keys(old_key: :value, new_key: :token_age_consumed)
  end

  @doc ~S"""
  Return the average age of the tokens that were transacted for the given slug and time period.
  """
  def average_token_age_consumed_in_days(
        root,
        %{slug: _, from: _, to: _, interval: _} = args,
        resolution
      ) do
    with {:ok, age_consumed} <- token_age_consumed(root, args, resolution),
         {:ok, transaction_volume} <- transaction_volume(root, args, resolution) do
      average_token_age_consumed_in_days =
        Enum.zip(age_consumed, transaction_volume)
        |> Enum.map(fn {%{token_age_consumed: token_age_consumed, datetime: datetime},
                        %{transaction_volume: trx_volume}} ->
          %{
            datetime: datetime,
            token_age: token_age_in_days(token_age_consumed, trx_volume)
          }
        end)

      {:ok, average_token_age_consumed_in_days}
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
    |> Sanbase.Utils.Transform.rename_map_keys(old_key: :value, new_key: :transaction_volume)
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
    |> Sanbase.Utils.Transform.rename_map_keys(old_key: :value, new_key: :in_out_difference)
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
    |> Sanbase.Utils.Transform.rename_map_keys(old_key: :value, new_key: :token_velocity)
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

  defp token_age_in_days(token_age_consumed, trx_volume)
       when token_age_consumed <= 0.1 or trx_volume <= 0.1 do
    0
  end

  defp token_age_in_days(token_age_consumed, trx_volume) do
    token_age_consumed / trx_volume
  end
end
