defmodule SanbaseWeb.Graphql.Resolvers.PostResolver do
  require Logger

  alias Sanbase.Auth.User
  alias Sanbase.Voting.{Poll, Post, Vote}
  alias Sanbase.Repo
  alias Sanbase.InternalServices.Ethauth
  alias SanbaseWeb.Graphql.Resolvers.Helpers

  def all_posts(_root, _args, _context) do
    posts = Post |> Repo.all()

    {:ok, posts}
  end
end
