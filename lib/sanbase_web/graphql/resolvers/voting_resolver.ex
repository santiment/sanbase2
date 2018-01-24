defmodule SanbaseWeb.Graphql.Resolvers.VotingResolver do
  require Logger

  alias Sanbase.Auth.User
  alias Sanbase.Voting.{Poll, Post, Vote}
  alias Sanbase.Repo

  def current_poll(_root, _args, _context) do
    poll = Poll.find_or_insert_current_poll!()
    |> Repo.preload(posts: :user)

    {:ok, poll}
  end

  def total_san_votes(%Post{} = post, _args, _context) do
    total_san_votes = post.votes
    |> Enum.map(&(Map.get(&1, :user)))
    |> Enum.map(&User.san_balance!/1)
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    {:ok, total_san_votes}
  end

  def vote(_root, %{post_id: post_id}, %{
        context: %{auth: %{current_user: user}}
      }) do

    %Vote{}
    |> Vote.changeset(%{post_id: post_id, user_id: user.id})
    |> Repo.insert
    |> case do
      {:ok, _vote} -> {:ok, Repo.get(Post, post_id)}
      {:error, error} -> {:error, error}
    end
  end

  def unvote(_root, %{post_id: post_id}, %{
        context: %{auth: %{current_user: user}}
      }) do

    with {:ok, vote} <- Repo.get_by(Vote, post_id: post_id, user_id: user.id),
         {:ok, _vote} <- Repo.delete(vote) do
      {:ok, Repo.get(Post, post_id)}
    else
      _ ->
        {:error, "Can't unvote this post"}
    end
  end
end
