defmodule Sanbase.Model.Project.ListSelector do
  alias Sanbase.Model.Project
  alias __MODULE__.{Transform, Validator}

  defdelegate valid_selector?(args), to: Validator

  @doc ~s"""
  Return a list of projects described by the selector object.

  See `args_to_opts/1` for description of the argument format.
  """
  def projects(args) do
    opts = args_to_opts(args)
    projects = Project.List.projects(opts)

    {:ok,
     %{
       projects: Project.List.projects(opts),
       total_projects_count: total_projects_count(projects, opts),
       has_pagination?: Keyword.get(opts, :has_pagination?),
       all_included_slugs: Keyword.get(opts, :included_slugs)
     }}
  end

  @doc ~s"""
  Return a list of slugs described by the selector object.

  See `args_to_opts/1` for description of the argument format.
  """
  def slugs(args) do
    opts = args_to_opts(args)
    slugs = Project.List.projects_slugs(opts)

    {:ok,
     %{
       slugs: slugs,
       total_projects_count: total_projects_count(slugs, opts)
     }}
  end

  @doc ~s"""
  Transform a selector to a keyword list that can be passed to the functions
  in the `Project.List` module to apply filtering/ordering/pagination.

  The argument is a map in the following format:
  %{
    selector: %{
      filters: [
        %{
          metric: "daily_active_addresses",
          from: ~U[2020-04-22 00:00:00Z],
          to: ~U[2020-04-29 00:00:00Z],
          aggregation: :avg,
          operator: :greater_than,
          threshold: 10
        }
      ],
      order_by: %{
        metric: "circulation",
        from: ~U[2020-04-25 00:00:00Z],
        to: ~U[2020-04-29 00:00:00Z],
        aggregation: :last
        direction: :desc
      },
      pagination: %{page: 1, page_size: 10}
    }
  }
  """
  def args_to_opts(args) do
    args = Sanbase.MapUtils.atomize_keys(args)

    filters = Transform.args_to_filters(args)
    base_projects_selector = Transform.args_to_base_projects(args)
    order_by = Transform.args_to_order_by(args)
    pagination = Transform.args_to_pagination(args)
    filters_combinator = Transform.args_to_filters_combinator(args)

    base_slugs = base_slugs(base_projects_selector)

    included_slugs =
      filters
      |> included_slugs_by_filters(filters_combinator)
      |> intersect_with_base_slugs(base_slugs)

    ordered_slugs = order_by |> ordered_slugs_by_order_by(included_slugs)

    [
      has_selector?: not is_nil(args[:selector]),
      has_order?: not is_nil(order_by),
      has_pagination?: not is_nil(pagination),
      pagination: pagination,
      min_volume: Map.get(args, :min_volume),
      included_slugs: included_slugs,
      ordered_slugs: ordered_slugs
    ]
  end

  # Private functions

  defp intersect_with_base_slugs(slugs, :all), do: slugs

  defp intersect_with_base_slugs(slugs, base_slugs) do
    MapSet.intersection(MapSet.new(slugs), MapSet.new(base_slugs))
    |> Enum.to_list()
  end

  defp total_projects_count(list, opts) do
    with true <- Keyword.get(opts, :has_pagination?),
         slugs when is_list(slugs) <- Keyword.get(opts, :included_slugs) do
      length(slugs)
    else
      _ -> length(list)
    end
  end

  defp detect_cycles!(args) do
    case Process.get(:__get_base_projects__) do
      nil ->
        Process.put(:__get_base_projects__, %{
          iterations_left: 5,
          args_seen_so_far: MapSet.new([args])
        })

      %{iterations_left: 0} ->
        raise("The base projects nesting of a watchlist is too deep.")

      %{iterations_left: iterations_left, args_seen_so_far: args_seen_so_far} ->
        case MapSet.member?(args_seen_so_far, args) do
          true ->
            raise("There is a cycle in the base_projects of watchlists.")

          false ->
            Process.put(:__get_base_projects__, %{
              iterations_left: iterations_left - 1,
              args_seen_so_far: MapSet.put(args_seen_so_far, args)
            })
        end
    end
  end

  defp base_slugs(:all), do: :all

  defp base_slugs(args_list) do
    Enum.flat_map(args_list, fn args ->
      {:ok, slugs} = get_base_slugs(args)
      slugs
    end)
  end

  defp get_base_slugs(%{watchlist_id: id} = map) do
    detect_cycles!(map)
    id |> Sanbase.UserList.by_id() |> Sanbase.UserList.get_slugs()
  end

  defp get_base_slugs(%{watchlist_slug: slug} = map) do
    detect_cycles!(map)
    slug |> Sanbase.UserList.by_slug() |> Sanbase.UserList.get_slugs()
  end

  defp get_base_slugs(%{slugs: slugs}) when is_list(slugs) do
    {:ok, slugs}
  end

  defp included_slugs_by_filters([], _filters_combinator), do: :all

  defp included_slugs_by_filters(filters, filters_combinator) when is_list(filters) do
    slug_mapsets =
      filters
      |> Sanbase.Parallel.map(
        fn filter ->
          cache_key = {:included_slugs_by_filter, filter}
          {:ok, slugs} = Sanbase.Cache.get_or_store(cache_key, fn -> slugs_by_filter(filter) end)

          slugs |> MapSet.new()
        end,
        ordered: false,
        max_concurrency: 8
      )

    case filters_combinator do
      "and" ->
        slug_mapsets
        |> Enum.reduce(&MapSet.intersection(&1, &2))
        |> Enum.to_list()

      "or" ->
        slug_mapsets
        |> Enum.reduce(&MapSet.union(&1, &2))
        |> Enum.to_list()
    end
  end

  defp slugs_by_filter(%{name: "market_segments", args: args}) do
    combinator = Map.get(args, :market_segments_combinator, "and")

    projects =
      case combinator do
        "and" -> Project.List.by_market_segment_all_of(args.market_segments)
        "or" -> Project.List.by_market_segment_any_of(args.market_segments)
      end

    slugs = Enum.map(projects, & &1.slug)
    {:ok, slugs}
  end

  defp slugs_by_filter(%{name: "metric", args: args}) do
    Sanbase.Metric.slugs_by_filter(
      args.metric,
      args.from,
      args.to,
      args.operator,
      args.threshold,
      aggregation: args.aggregation
    )
  end

  defp slugs_by_filter(%{metric: _} = filter) do
    Sanbase.Metric.slugs_by_filter(
      filter.metric,
      filter.from,
      filter.to,
      filter.operator,
      filter.threshold,
      aggregation: filter.aggregation
    )
  end

  defp ordered_slugs_by_order_by(nil, slugs), do: slugs

  defp ordered_slugs_by_order_by(order_by, slugs) do
    %{metric: metric, from: from, to: to, direction: direction} = order_by
    aggregation = Map.get(order_by, :aggregation)

    {:ok, ordered_slugs} =
      Sanbase.Metric.slugs_order(metric, from, to, direction, aggregation: aggregation)

    case slugs do
      :all ->
        ordered_slugs

      ^slugs when is_list(slugs) ->
        slugs_mapset = slugs |> MapSet.new()
        Enum.filter(ordered_slugs, &(&1 in slugs_mapset))
    end
  end
end
