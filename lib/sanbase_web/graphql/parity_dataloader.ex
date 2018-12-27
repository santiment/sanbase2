defmodule SanbaseWeb.Graphql.ParityDataloader do
  alias Sanbase.InternalServices.Parity
  alias Sanbase.Model.Project

  import Ecto.Query

  def data() do
    Dataloader.KV.new(&fetch/2)
  end

  def fetch(_batch_key, arg_maps) do
    addresses =
      Enum.flat_map(arg_maps, fn project ->
        {:ok, eth_addresses} = Project.eth_addresses(project)
        eth_addresses
      end)

    Parity.get_eth_balance(addresses)
  end
end
