defmodule SanbaseWeb.Graphql.Resolvers.EthAccountResolver do
  alias Sanbase.Auth.EthAccount
  alias Sanbase.InternalServices.Ethauth

  def san_balance(eth_account, _, _) do
    {:ok, EthAccount.san_balance(eth_account)}
  end
end
