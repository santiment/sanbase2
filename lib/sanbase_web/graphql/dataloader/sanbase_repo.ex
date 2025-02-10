defmodule SanbaseWeb.Graphql.SanbaseRepo do
  import Ecto.Query

  alias Sanbase.Insight.Post
  alias Sanbase.Project
  alias Sanbase.Repo
  alias Sanbase.Timeline.TimelineEvent

  @spec data() :: Dataloader.Ecto.t()
  def data do
    Dataloader.Ecto.new(Repo, query: &query/2)
  end

  def query(Project, _args) do
    preload(Project, ^Project.preloads())
  end

  def query(Post, _args) do
    preload(Post, [:votes])
  end

  def query(TimelineEvent, _args) do
    preload(TimelineEvent, [:votes])
  end

  def query(queryable, _args) do
    queryable
  end
end
