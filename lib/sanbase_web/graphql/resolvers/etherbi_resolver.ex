defmodule SanbaseWeb.Graphql.Resolvers.EtherbiResolver do
  require Sanbase.Utils.Config
  alias Sanbase.Utils.Config

  alias SanbaseWeb.Graphql.Resolvers.EtherbiApiResolver
  alias SanbaseWeb.Graphql.Resolvers.EtherbiCacheResolver

  @doc ~S"""
    Return the token burn rate for the given ticker and time period.
  """
  def burn_rate(root, args, resolution) do
    if use_cache?() do
      EtherbiCacheResolver.burn_rate(root, args, resolution)
    else
      EtherbiApiResolver.burn_rate(root, args, resolution)
    end
  end

  @doc ~S"""
    Return the transaction volume for the given ticker and time period.
  """
  def transaction_volume(root, args, resolution) do
    if use_cache?() do
      EtherbiCacheResolver.transaction_volume(root, args, resolution)
    else
      EtherbiApiResolver.transaction_volume(root, args, resolution)
    end
  end

  @doc ~S"""
    Return the transactions that happend in or out of an exchange wallet for a given ticker
    and time period.
  """
  def exchange_fund_flow(root, args, resolution) do
    if use_cache?() do
      EtherbiCacheResolver.exchange_fund_flow(root, args, resolution)
    else
      EtherbiApiResolver.exchange_fund_flow(root, args, resolution)
    end
  end

  # Private functions

  defp use_cache?() do
    Config.module_get(Sanbase.Etherbi, :use_cache)
  end
end
