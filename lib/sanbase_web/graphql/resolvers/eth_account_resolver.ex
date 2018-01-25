defmodule SanbaseWeb.Graphql.Resolvers.EthAccountResolver do
  alias Sanbase.Auth.EthAccount
  alias Sanbase.InternalServices.Ethauth

  def san_balance(eth_account, _, _) do
    {:ok, Decimal.div(EthAccount.san_balance(eth_account), Ethauth.san_token_decimals())}
  end
end
