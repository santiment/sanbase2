defmodule SanbaseWeb.Graphql.Resolvers.VoteResolver do
  import Absinthe.Resolution.Helpers, except: [async: 1]

  alias SanbaseWeb.Graphql.SanbaseDataloader
  alias Sanbase.Accounts.User
  alias Sanbase.Vote

  @doc ~s"""
  Returns a tuple `{total_votes, total_san_votes}` where:
  - `total_votes` represents the number of votes where each vote's weight is 1
  - `total_san_votes` represents the number of votes where each vote's weight is
  equal to the san balance of the voter
  """
  def votes(parent, _args, %{context: %{loader: loader} = context} = resolution) do
    user = get_in(context, [:auth, :current_user]) || %User{id: nil}

    case resolve_entity(parent, resolution) do
      {entity_id, selector_key, votes_query, _voted_at_query} ->
        get_votes(loader, votes_query, %{selector_key => entity_id, :user_id => user.id})

      nil ->
        {:ok, nil}
    end
  end

  def voted_at(
        parent,
        _args,
        %{context: %{loader: loader, auth: %{current_user: user}}} = resolution
      ) do
    case resolve_entity(parent, resolution) do
      {entity_id, selector_key, _votes_query, voted_at_query} ->
        get_voted_at(loader, voted_at_query, %{selector_key => entity_id, :user_id => user.id})

      nil ->
        {:ok, nil}
    end
  end

  def voted_at(_root, _args, _context), do: {:ok, nil}

  defp resolve_entity(parent, resolution) do
    Vote.dataloader_keys(parent) ||
      Vote.dataloader_keys(Map.get(resolution, :source) || %{})
  end

  # Private functions
  defp get_votes(loader, query, selector) do
    loader
    |> Dataloader.load(SanbaseDataloader, query, selector)
    |> on_load(fn loader ->
      result = Dataloader.get(loader, SanbaseDataloader, query, selector)

      result = result || %{total_votes: 0, total_voters: 0, current_user_votes: 0}

      {:ok, result}
    end)
  end

  defp get_voted_at(loader, query, selector) do
    loader
    |> Dataloader.load(SanbaseDataloader, query, selector)
    |> on_load(fn loader ->
      result = Dataloader.get(loader, SanbaseDataloader, query, selector)

      result = (result && result[:voted_at]) || nil

      {:ok, result}
    end)
  end

  defp only_one_entity_id?(args) do
    case Enum.reject(args, fn {_k, v} -> v == nil end) do
      [{key, value}] -> {:ok, entity_id_to_entity_name(key), value}
      _ -> {:error, "When voting/unvoting you must provide only one entity id."}
    end
  end

  defp entity_id_to_entity_name(entity_id) do
    case entity_id do
      :insight_id ->
        :post

      x ->
        x
        |> to_string()
        |> String.trim_trailing("_id")
        |> String.to_existing_atom()
    end
  end

  defp args_to_vote_args(args, user) do
    case args do
      %{insight_id: id} ->
        %{post_id: id, user_id: user.id}

      map ->
        Map.put(map, :user_id, user.id)
    end
  end

  def vote(_root, args, %{context: %{auth: %{current_user: user}}}) do
    with {:ok, entity, entity_id} <- only_one_entity_id?(args),
         :ok <- can_vote_for_entity(entity, entity_id, user.id),
         vote_args <- args_to_vote_args(args, user) do
      case Vote.create(vote_args) do
        {:ok, vote} ->
          voted_at = if vote.id, do: vote.inserted_at, else: nil
          {:ok, Map.put(vote_args, :voted_at, voted_at)}

        {:error, _} ->
          {:error, "Cannot vote for #{entity} with id #{entity_id}"}
      end
    end
  end

  def unvote(_root, args, %{context: %{auth: %{current_user: user}}}) do
    with {:ok, entity, entity_id} <- only_one_entity_id?(args),
         :ok <- can_vote_for_entity(entity, entity_id, user.id),
         vote_args <- args_to_vote_args(args, user) do
      case Vote.downvote(vote_args) do
        {:ok, vote} ->
          voted_at = if vote.id, do: vote.inserted_at, else: nil
          {:ok, Map.put(vote_args, :voted_at, voted_at)}

        {:error, _} ->
          {:error, "Cannot remove vote for #{entity} with id #{entity_id}"}
      end
    end
  end

  defp can_vote_for_entity(entity, entity_id, user_id) do
    entity_type = Sanbase.Entity.vote_entity_to_entity_type(entity)

    case Sanbase.Entity.get_visibility_data(entity_type, entity_id) do
      # Hidden entities (even public ones, and even those owned by the caller)
      # are treated as if they don't exist — voting on them would bring them
      # back into trending/leaderboard surfaces.
      {:ok, %{is_hidden: true}} ->
        not_visible_error(entity, entity_id)

      {:ok, %{user_id: ^user_id}} ->
        :ok

      {:ok, %{is_public: true}} ->
        :ok

      # Merge "private and not owned" and "does not exist" into one message
      # so an attacker cannot probe private entity IDs.
      _ ->
        not_visible_error(entity, entity_id)
    end
  end

  defp not_visible_error(entity, entity_id) do
    {:error,
     "The entity of type #{entity} with id #{entity_id} does not exist, " <>
       "or is private and not owned by you."}
  end
end
