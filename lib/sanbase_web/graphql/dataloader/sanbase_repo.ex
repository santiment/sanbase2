defmodule SanbaseWeb.Graphql.SanbaseRepo do
  alias Sanbase.Repo
  alias Sanbase.Project
  alias Sanbase.Insight.Post
  alias Sanbase.Chat.{Chat, ChatMessage}

  import Ecto.Query

  @spec data() :: Dataloader.Ecto.t()
  def data() do
    # Timeout must live on the source — Dataloader ignores the loader-level
    # `Dataloader.new(timeout:)` option and derives its run timeout from
    # `Source.timeout/1`. Postgres query budget is 30s (config.exs), +5s
    # margin so the batch outlives its own query. See docs/timeouts.md.
    Dataloader.Ecto.new(Repo, query: &query/2, timeout: :timer.seconds(35))
  end

  def query(Project, _args) do
    Project
    |> preload(^Project.preloads())
  end

  def query(Post, _args) do
    Post
    |> preload([:votes])
  end

  def query(Chat, _args) do
    Chat
    |> preload([:user, :chat_messages])
  end

  def query(ChatMessage, _args) do
    ChatMessage
    |> preload([:chat])
  end

  def query(queryable, _args) do
    queryable
  end
end
