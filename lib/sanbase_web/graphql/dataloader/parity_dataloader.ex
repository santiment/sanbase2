defmodule SanbaseWeb.Graphql.ParityDataloader do
  alias Sanbase.InternalServices.Parity
  alias Sanbase.Model.Project

  def data() do
    Dataloader.KV.new(&query/2)
  end

  def query(:eth_balance, projects) do
    addresses =
      Enum.flat_map(projects, fn project ->
        {:ok, eth_addresses} = Project.eth_addresses(project)
        eth_addresses
      end)

    Parity.get_eth_balance(addresses)
  end
end
