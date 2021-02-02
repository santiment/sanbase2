defmodule SanbaseWeb.Graphql.Resolvers.EthAccountResolver do
  alias Sanbase.Accounts.EthAccount

  def san_balance(eth_account, _, _) do
    {:ok, EthAccount.san_balance(eth_account)}
  end
end
