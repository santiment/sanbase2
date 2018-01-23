defmodule SanbaseWeb.Graphql.Resolvers.VotingResolver do
  require Logger

  alias Sanbase.Auth.User
  alias Sanbase.Voting.{Poll, Post}

  def current_poll(_root, _args, _context) do
    {:ok, Poll.find_or_insert_current_poll!()}
  end

  def total_san_votes(%Post{} = post, _args, _context) do
    total_san_votes = post.votes
    |> Enum.map(&(Map.get(&1, :user)))
    |> Enum.map(&User.san_balance!/1)

    {:ok, total_san_votes}
  end
end
