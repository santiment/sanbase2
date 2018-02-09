defmodule SanbaseWeb.Graphql.SanbaseRepo do
  alias Sanbase.Repo
  alias Sanbase.Model.{ProjectEthAddress, ProjectBtcAddress}

  import Ecto.Query

  def data() do
    Dataloader.Ecto.new(Repo, query: &query/2)
  end

  def query(ProjectEthAddress, _params) do
    ProjectEthAddress
    |> preload([:latest_eth_wallet_data])
  end

  def query(ProjectBtcAddress, _params) do
    ProjectBtcAddress
    |> preload([:latest_btc_wallet_data])
  end

  def query(queryable, _params) do
    queryable
  end
end
