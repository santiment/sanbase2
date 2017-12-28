defmodule SanbaseWeb.Graphql.Resolvers.EthAccountResolver do
  alias Sanbase.Auth.EthAccount

  import Absinthe.Resolution.Helpers, only: [async: 1]

  def san_balance(eth_account, _, _) do
    async(fn ->
      {:ok, EthAccount.san_balance(eth_account)}
    end)
  end
end