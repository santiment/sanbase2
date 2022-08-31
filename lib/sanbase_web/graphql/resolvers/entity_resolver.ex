defmodule SanbaseWeb.Graphql.Resolvers.EntityResolver do
  import Sanbase.Utils.Transform, only: [maybe_apply_function: 2]
  import SanbaseWeb.Graphql.Helpers.Utils, only: [transform_user_trigger: 1]

  def store_user_entity_interaction(_root, args, %{context: %{auth: %{current_user: user}}}) do
    args = Map.take(args, [:entity_id, :entity_type, :interaction_type])

    case Sanbase.Accounts.Interaction.store_user_interaction(user.id, args) do
      {:ok, _} -> {:ok, true}
      {:error, error} -> {:error, Sanbase.Utils.ErrorHandling.changeset_errors_string(error)}
    end
  end

  # Start Most Voted

  def get_most_voted(_root, args, _resolution) do
    maybe_do_not_cache(args)

    {:ok, %{query: :get_most_voted, args: args}}
  end

  def get_most_voted_data(_root, _args, resolution) do
    %{source: %{args: args}} = resolution
    types = get_types(args)
    opts = get_opts(args, resolution)

    Sanbase.Entity.get_most_voted(types, opts)
    |> maybe_extend_with_views_count(opts)
    |> maybe_apply_function(&handle_result/1)
  end

  def get_most_voted_stats(_root, _args, resolution) do
    %{source: %{args: args}} = resolution
    maybe_do_not_cache(args)

    types = get_types(args)
    opts = get_opts(args, resolution)
    {:ok, total_entities_count} = Sanbase.Entity.get_most_voted_total_count(types, opts)

    stats = %{
      current_page: opts[:page],
      current_page_size: opts[:page_size],
      total_pages_count: (total_entities_count / opts[:page_size]) |> Float.ceil() |> trunc(),
      total_entities_count: total_entities_count
    }

    {:ok, stats}
  end

  # End Most Voted

  # Start Most Recent

  def get_most_recent_data(_root, _args, %{source: %{args: args}} = resolution) do
    maybe_do_not_cache(args)
    types = get_types(args)
    opts = get_opts(args, resolution)

    Sanbase.Entity.get_most_recent(types, opts)
    |> maybe_extend_with_views_count(opts)
    |> maybe_apply_function(&handle_result/1)
  end

  def get_most_recent_stats(_root, _args, %{source: %{args: args}} = resolution) do
    maybe_do_not_cache(args)

    types = get_types(args)
    opts = get_opts(args, resolution)
    {:ok, total_entities_count} = Sanbase.Entity.get_most_recent_total_count(types, opts)

    stats = %{
      current_page: opts[:page],
      current_page_size: opts[:page_size],
      total_pages_count: (total_entities_count / opts[:page_size]) |> Float.ceil() |> trunc(),
      total_entities_count: total_entities_count
    }

    {:ok, stats}
  end

  def get_most_recent(_root, args, _resolution) do
    maybe_do_not_cache(args)
    {:ok, %{query: :get_most_recent, args: args}}
  end

  # End Most Recent

  # Start Most Used

  def get_most_used(_root, args, _resolution) do
    maybe_do_not_cache(args)
    {:ok, %{query: :get_most_used, args: args}}
  end

  def get_most_used_data(_root, _args, %{source: %{args: args}} = resolution) do
    maybe_do_not_cache(args)
    types = get_types(args)
    opts = get_opts(args, resolution)

    Sanbase.Entity.get_most_used(types, opts)
    |> maybe_extend_with_views_count(opts)
    |> maybe_apply_function(&handle_result/1)
  end

  def get_most_used_stats(_root, _args, resolution) do
    %{source: %{args: args}} = resolution
    maybe_do_not_cache(args)

    types = get_types(args)
    opts = get_opts(args, resolution)
    {:ok, total_entities_count} = Sanbase.Entity.get_most_used_total_count(types, opts)

    stats = %{
      current_page: opts[:page],
      current_page_size: opts[:page_size],
      total_pages_count: (total_entities_count / opts[:page_size]) |> Float.ceil() |> trunc(),
      total_entities_count: total_entities_count
    }

    {:ok, stats}
  end

  # End Most Used

  defp handle_result(list) do
    Enum.map(list, fn map ->
      case Map.to_list(map) do
        [{:user_trigger, entity}] -> %{:user_trigger => transform_user_trigger(entity)}
        _ -> map
      end
    end)
  end

  defp get_types(args) do
    Map.get(args, :types) || [Map.get(args, :type)]
  end

  defp get_opts(args, resolution) do
    [
      page: Map.get(args, :page, 1),
      page_size: Map.get(args, :page_size, 10),
      cursor: Map.get(args, :cursor),
      filter: Map.get(args, :filter)
    ]
    |> maybe_add_user_id_option(resolution)
    |> maybe_add_user_option(:current_user_data_only, args, resolution)
    |> maybe_add_user_option(:current_user_voted_for_only, args, resolution)
    |> maybe_add_value_option(:user_role_data_only, args)
    |> maybe_add_value_option(:is_featured_data_only, args)
    |> add_is_moderator_option(resolution)
  end

  defp maybe_add_user_id_option(opts, resolution) do
    case get_in(resolution.context.auth, [:current_user, Access.key(:id)]) do
      nil -> opts
      user_id -> Keyword.put(opts, :current_user_id, user_id)
    end
  end

  defp maybe_add_user_option(opts, key, args, resolution) do
    with true <- Map.get(args, key, false),
         user_id when is_integer(user_id) <-
           get_in(resolution.context.auth, [:current_user, Access.key(:id)]) do
      Keyword.put(opts, key, user_id)
    else
      _ -> opts
    end
  end

  defp maybe_add_value_option(opts, key, args) do
    case Map.has_key?(args, key) do
      true -> Keyword.put(opts, key, Map.get(args, key))
      false -> opts
    end
  end

  defp add_is_moderator_option(opts, resolution) do
    is_moderator = Map.get(resolution.context, :is_moderator)
    Keyword.put(opts, :is_moderator, is_moderator)
  end

  defp maybe_extend_with_views_count({:ok, result}, opts) do
    case Keyword.get(opts, :is_moderator, false) do
      true -> {:ok, Sanbase.Entity.extend_with_views_count(result)}
      false -> {:ok, result}
    end
  end

  defp maybe_extend_with_views_count(result, _opts), do: result

  defp maybe_do_not_cache(args) do
    # Do not cache the queries that fetch the users' own data as they differ
    # for every user and the cache key does not take into consideration the user id
    if Map.get(args, :current_user_data_only) || Map.get(args, :current_user_voted_for_only),
      do: Process.put(:do_not_cache_query, true)
  end
end
