defmodule SanbaseWeb.Graphql.Resolvers.VotingResolver do
  require Logger

  alias Sanbase.Auth.User
  alias Sanbase.Voting.{Poll, Post, Vote}
  alias Sanbase.Repo
  alias Sanbase.InternalServices.Ethauth
  alias SanbaseWeb.Graphql.Resolvers.Helpers

  def current_poll(_root, _args, _context) do
    poll =
      Poll.find_or_insert_current_poll!()
      |> Repo.preload(posts: :user)

    {:ok, poll}
  end

  def total_san_votes(%Post{} = post, _args, _context) do
    total_san_votes =
      post
      |> Repo.preload(votes: [user: :eth_accounts])
      |> Map.get(:votes)
      |> Enum.map(&Map.get(&1, :user))
      |> Enum.map(&User.san_balance!/1)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    {:ok, Decimal.div(total_san_votes, Ethauth.san_token_decimals())}
  end

  def voted_at(%Post{} = post, _args, %{
        context: %{auth: %{current_user: user}}
      }) do
    case Repo.get_by(Vote, post_id: post.id, user_id: user.id) do
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
          message: "Can't vote for post #{post_id}", details: Helpers.error_details(changeset)
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

  def create_post(_root, post_args, %{
        context: %{auth: %{current_user: user}}
      }) do
    %Post{user_id: user.id, poll_id: Poll.find_or_insert_current_poll!().id}
    |> Post.changeset(post_args)
    |> Repo.insert()
    |> case do
      {:ok, post} ->
        {:ok, post |> Repo.preload([:votes, :user])}

      {:error, changeset} ->
        {
          :error,
          message: "Can't create post", details: Helpers.error_details(changeset)
        }
    end
  end

  def delete_post(_root, %{id: post_id}, %{
        context: %{auth: %{current_user: %User{id: user_id}}}
      }) do
    case Repo.get(Post, post_id) do
      %Post{user_id: ^user_id} = post ->
        Repo.delete(post)
        {:ok, post}

      post ->
        {:error, "You don't own post #{post.id}"}
    end
  end
end
