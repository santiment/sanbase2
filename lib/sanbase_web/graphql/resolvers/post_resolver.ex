defmodule SanbaseWeb.Graphql.Resolvers.PostResolver do
  require Logger

  import Ecto.Query

  alias Sanbase.Auth.User
  alias Sanbase.Voting.{Poll, Post, Vote}
  alias Sanbase.Repo
  alias Sanbase.InternalServices.Ethauth
  alias SanbaseWeb.Graphql.Resolvers.Helpers

  def all_posts(_root, _args, _context) do
    posts = Post |> Repo.all()

    {:ok, posts}
  end

  def all_posts_for_user(_root, %{user_id: user_id}, _context) do
    query =
      from(
        p in Post,
        where: p.user_id == ^user_id
      )

    posts = query |> Repo.all()
    {:ok, posts}
  end
end
