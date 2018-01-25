defmodule SanbaseWeb.Graphql.Resolvers.VotingResolver do
  require Logger

  alias Sanbase.Auth.User
  alias Sanbase.Voting.{Poll, Post, Vote}
  alias Sanbase.Repo

  def current_poll(_root, _args, _context) do
    poll =
      Poll.find_or_insert_current_poll!()
      |> Repo.preload(posts: :user)

    {:ok, poll}
  end

  def total_san_votes(%Post{} = post, _args, _context) do
    total_san_votes =
      post
      |> Repo.preload(votes: [:user])
      |> Map.get(:votes)
      |> Enum.map(&Map.get(&1, :user))
      |> Enum.map(&User.san_balance!/1)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    {:ok, total_san_votes}
  end

  def approved_posts(poll, _args, _context) do
    approved_posts =
      poll.posts
      |> Enum.reject(&is_nil(&1.approved_at))

    {:ok, approved_posts}
  end

  def vote(_root, %{post_id: post_id}, %{
        context: %{auth: %{current_user: user}}
      }) do
    %Vote{}
    |> Vote.changeset(%{post_id: post_id, user_id: user.id})
    |> Repo.insert()
    |> case do
      {:ok, _vote} -> {:ok, Repo.get(Post, post_id)}
      {:error, error} -> {:error, error}
    end
  end

  def unvote(_root, %{post_id: post_id}, %{
        context: %{auth: %{current_user: user}}
      }) do
    with %Vote{} = vote <- Repo.get_by(Vote, post_id: post_id, user_id: user.id),
         {:ok, _vote} <- Repo.delete(vote) do
      {:ok, Repo.get(Post, post_id)}
    else
      _error ->
        {:error, "Can't remove vote"}
    end
  end

  def create_post(_root, post_args, %{
        context: %{auth: %{current_user: user}}
      }) do
    %Post{user_id: user.id, poll_id: Poll.find_or_insert_current_poll!().id}
    |> Post.changeset(post_args)
    |> Repo.insert()
    |> case do
      {:ok, post} ->
        {:ok, post |> Repo.preload([:votes, :user])}

      {:error, %{errors: errors}} ->
        {:error, errors}
    end
  end
end
