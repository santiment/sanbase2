defmodule SanbaseWeb.Graphql.SanbaseRepo do
  alias Sanbase.Repo
  alias Sanbase.Model.ProjectBtcAddress
  alias Sanbase.Voting.Post

  import Ecto.Query

  @spec data() :: Dataloader.Ecto.t()
  def data() do
    Dataloader.Ecto.new(Repo, query: &query/2)
  end

  def query(ProjectBtcAddress, _params) do
    ProjectBtcAddress
    |> preload([:latest_btc_wallet_data])
  end

  def query(Post, _params) do
    Post
    |> preload([:votes])
  end

  def query(queryable, _params) do
    queryable
  end
end
