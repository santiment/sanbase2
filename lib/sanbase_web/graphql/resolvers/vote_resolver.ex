defmodule SanbaseWeb.Graphql.Resolvers.VoteResolver do
  require Logger

  import Absinthe.Resolution.Helpers, except: [async: 1]

  alias SanbaseWeb.Graphql.SanbaseDataloader
  alias Sanbase.Accounts.User
  alias Sanbase.Vote
  alias Sanbase.Insight.Post
  alias Sanbase.Chart
  alias Sanbase.Alert.UserTrigger
  alias Sanbase.Timeline.TimelineEvent
  alias Sanbase.UserList

  require Logger

  @doc ~s"""
  Returns a tuple `{total_votes, total_san_votes}` where:
  - `total_votes` represents the number of votes where each vote's weight is 1
  - `total_san_votes` represents the number of votes where each vote's weight is
  equal to the san balance of the voter
  """
  def votes(%Post{} = post, _args, %{context: %{loader: loader} = context}) do
    user = get_in(context, [:auth, :current_user]) || %User{id: nil}
    selector = %{post_id: post.id, user_id: user.id}
    get_votes(loader, :insight_vote_stats, selector)
  end

  def votes(%UserList{} = ul, _args, %{context: %{loader: loader} = context}) do
    user = get_in(context, [:auth, :current_user]) || %User{id: nil}
    selector = %{watchlist_id: ul.id, user_id: user.id}
    get_votes(loader, :watchlist_vote_stats, selector)
  end

  def votes(%Chart.Configuration{} = config, _args, %{
        context: %{loader: loader} = context
      }) do
    user = get_in(context, [:auth, :current_user]) || %User{id: nil}
    selector = %{chart_configuration_id: config.id, user_id: user.id}

    get_votes(loader, :chart_configuration_vote_stats, selector)
  end

  def votes(%Sanbase.Dashboard.Schema{} = dashboard, _args, %{
        context: %{loader: loader} = context
      }) do
    user = get_in(context, [:auth, :current_user]) || %User{id: nil}
    selector = %{dashboard_id: dashboard.id, user_id: user.id}

    get_votes(loader, :dashboard_vote_stats, selector)
  end

  def votes(%Sanbase.Queries.Dashboard{} = dashboard, _args, %{
        context: %{loader: loader} = context
      }) do
    user = get_in(context, [:auth, :current_user]) || %User{id: nil}
    selector = %{dashboard_id: dashboard.id, user_id: user.id}

    get_votes(loader, :dashboard_vote_stats, selector)
  end

  def votes(%{trigger: %{id: user_trigger_id}}, _args, %{
        context: %{loader: loader} = context
      })
      when is_integer(user_trigger_id) do
    user = get_in(context, [:auth, :current_user]) || %User{id: nil}
    selector = %{user_trigger_id: user_trigger_id, user_id: user.id}

    get_votes(loader, :user_trigger_vote_stats, selector)
  end

  def votes(%UserTrigger{id: user_trigger_id}, _args, %{
        context: %{loader: loader} = context
      })
      when is_integer(user_trigger_id) do
    user = get_in(context, [:auth, :current_user]) || %User{id: nil}
    selector = %{user_trigger_id: user_trigger_id, user_id: user.id}

    get_votes(loader, :user_trigger_vote_stats, selector)
  end

  def votes(%TimelineEvent{} = event, _args, %{
        context: %{loader: loader} = context
      }) do
    user = get_in(context, [:auth, :current_user]) || %User{id: nil}
    selector = %{timeline_event_id: event.id, user_id: user.id}

    get_votes(loader, :timeline_event_vote_stats, selector)
  end

  def votes(_root, args, %{source: %{post_id: id}} = resolution) do
    # Handles the case where the `votes` is called on top of the result
    # from `vote`/`unvote`. They return the entity id as a result which
    # can be used from the `source` map in the resolution
    votes(%Post{id: id}, args, resolution)
  end

  def votes(_root, args, %{source: %{watchlist_id: id}} = resolution) do
    # Handles the case where the `votes` is called on top of the result
    # from `vote`/`unvote`. They return the entity id as a result which
    # can be used from the `source` map in the resolution
    votes(%UserList{id: id}, args, resolution)
  end

  def votes(_root, args, %{source: %{chart_configuration_id: id}} = resolution) do
    # Handles the case where the `votes` is called on top of the result
    # from `vote`/`unvote`. They return the entity id as a result which
    # can be used from the `source` map in the resolution
    votes(%Chart.Configuration{id: id}, args, resolution)
  end

  def votes(_root, args, %{source: %{dashboard_id: id}} = resolution) do
    # Handles the case where the `votes` is called on top of the result
    # from `vote`/`unvote`. They return the entity id as a result which
    # can be used from the `source` map in the resolution
    votes(%Sanbase.Queries.Dashboard{id: id}, args, resolution)
  end

  def votes(_root, args, %{source: %{user_trigger_id: id}} = resolution) do
    # Handles the case where the `votes` is called on top of the result
    # from `vote`/`unvote`. They return the entity id as a result which
    # can be used from the `source` map in the resolution
    votes(%UserTrigger{id: id}, args, resolution)
  end

  def votes(_root, args, %{source: %{timeline_event_id: id}} = resolution) do
    # Handles the case where the `votes` is called on top of the result
    # from `vote`/`unvote`. They return the entity id as a result which
    # can be used from the `source` map in the resolution
    votes(%TimelineEvent{id: id}, args, resolution)
  end

  def voted_at(%Post{} = post, _args, %{
        context: %{loader: loader, auth: %{current_user: user}}
      }) do
    selector = %{post_id: post.id, user_id: user.id}
    get_voted_at(loader, :insight_voted_at, selector)
  end

  def voted_at(%UserList{} = ul, _args, %{
        context: %{loader: loader, auth: %{current_user: user}}
      }) do
    selector = %{watchlist_id: ul.id, user_id: user.id}
    get_voted_at(loader, :watchlist_voted_at, selector)
  end

  def voted_at(%TimelineEvent{} = event, _args, %{
        context: %{loader: loader, auth: %{current_user: user}}
      }) do
    selector = %{timeline_event_id: event.id, user_id: user.id}
    get_voted_at(loader, :timeline_event_voted_at, selector)
  end

  def voted_at(%Chart.Configuration{} = config, _args, %{
        context: %{loader: loader, auth: %{current_user: user}}
      }) do
    selector = %{chart_configuration_id: config.id, user_id: user.id}
    get_voted_at(loader, :chart_configuration_voted_at, selector)
  end

  def voted_at(%Sanbase.Dashboard.Schema{} = config, _args, %{
        context: %{loader: loader, auth: %{current_user: user}}
      }) do
    selector = %{dashboard_id: config.id, user_id: user.id}
    get_voted_at(loader, :dashboard_voted_at, selector)
  end

  def voted_at(%Sanbase.Queries.Dashboard{} = config, _args, %{
        context: %{loader: loader, auth: %{current_user: user}}
      }) do
    selector = %{dashboard_id: config.id, user_id: user.id}
    get_voted_at(loader, :dashboard_voted_at, selector)
  end

  def voted_at(%{trigger: %{id: id}}, _args, %{
        context: %{loader: loader, auth: %{current_user: user}}
      }) do
    selector = %{user_trigger_id: id, user_id: user.id}
    get_voted_at(loader, :user_trigger_voted_at, selector)
  end

  def voted_at(%UserTrigger{id: id}, _args, %{
        context: %{loader: loader, auth: %{current_user: user}}
      }) do
    selector = %{user_trigger_id: id, user_id: user.id}
    get_voted_at(loader, :user_trigger_voted_at, selector)
  end

  def voted_at(_root, _args, _context), do: {:ok, nil}

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
end
