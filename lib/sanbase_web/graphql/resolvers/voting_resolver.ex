defmodule SanbaseWeb.Graphql.Resolvers.VotingResolver do
  require Logger

  alias Sanbase.Auth.User
  alias Sanbase.Voting.{Poll, Post, Vote}
  alias Sanbase.Repo
  alias SanbaseWeb.Graphql.Helpers.Utils

  def current_poll(_root, _args, _context) do
    poll =
      Poll.find_or_insert_current_poll!()
      |> Repo.preload(posts: :user)

    {:ok, poll}
  end

  @doc ~s"""
    Returns a tuple `{total_votes, total_san_votes}` where:
    - `total_votes` represents the number of votes where each vote's weight is 1
    - `total_san_votes` represents the number of votes where each vote's weight is
    equal to the san balance of the voter
  """
  def votes(%Post{} = post, _args, _context) do
    {total_votes, total_san_votes} =
      post
      |> Repo.preload(votes: [user: :eth_accounts])
      |> Map.get(:votes)
      |> Stream.map(&Map.get(&1, :user))
      |> Stream.map(&User.san_balance!/1)
      |> Enum.reduce({0, 0}, fn san_balance, {votes, san_token_votes} ->
        {votes + 1, san_token_votes + Decimal.to_float(san_balance)}
      end)

    {:ok,
     %{
       total_votes: total_votes,
       total_san_votes: total_san_votes |> round() |> trunc()
     }}
  end

  def voted_at(%Post{} = post, _args, %{
        context: %{auth: %{current_user: user}}
      }) do
    post
    |> Repo.preload([:votes])
    |> Map.get(:votes, [])
    |> Enum.find(&(&1.user_id == user.id))
    |> case do
      nil -> {:ok, nil}
      vote -> {:ok, vote.inserted_at}
    end
  end

  def voted_at(%Post{}, _args, _context), do: {:ok, nil}

  def vote(_root, %{post_id: post_id}, %{
        context: %{auth: %{current_user: user}}
      }) do
    %Vote{}
    |> Vote.changeset(%{post_id: post_id, user_id: user.id})
    |> Repo.insert()
    |> case do
      {:ok, _vote} ->
        {:ok, Repo.get(Post, post_id)}

      {:error, changeset} ->
        {
          :error,
          message: "Can't vote for post #{post_id}", details: Utils.error_details(changeset)
        }
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
end
