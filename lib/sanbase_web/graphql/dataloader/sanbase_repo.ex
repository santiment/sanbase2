defmodule SanbaseWeb.Graphql.SanbaseRepo do
  alias Sanbase.Repo
  alias Sanbase.Model.{ProjectBtcAddress, Project}
  alias Sanbase.Voting.Post

  import Ecto.Query

  @spec data() :: Dataloader.Ecto.t()
  def data() do
    Dataloader.Ecto.new(Repo, query: &query/2)
  end

  def query(ProjectBtcAddress, _args) do
    ProjectBtcAddress
    |> preload([:latest_btc_wallet_data])
  end

  def query(Project, args) do
    Project
    |> preload(^Project.preloads())
  end

  def query(Post, _args) do
    Post
    |> preload([:votes])
  end

  def query(queryable, _args) do
    queryable
  end
end
