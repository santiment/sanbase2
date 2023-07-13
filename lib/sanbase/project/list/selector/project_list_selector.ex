defmodule Sanbase.Project.ListSelector do
  @moduledoc ~s"""
  Module that resolved a selector object to a list of projects.


  """
  alias Sanbase.Project
  alias Sanbase.Utils.ListSelector.Transform

  # Important note:
  # #TODO: Rework this
  # Currently, the caller must make sure that every different watchlist is resolved
  # in a different process or call clear_detect_cycles/0 function.
  # This is because in order to detect cycles, some storage must be used to keep
  # data between calls. For this purposes the process dictionary is used. This can
  # lead to issues if more than 1 watchlist is resolved.
  @cycle_detection_key :__get_base_projects__
  def clear_detect_cycles(), do: Process.delete(@cycle_detection_key)

  defdelegate valid_selector?(args), to: __MODULE__.Validator

  @doc ~s"""
  Return a list of projects described by the selector object.

  See `args_to_opts/1` for description of the argument format.
  """
  def projects(args) do
    with {:ok, opts} <- args_to_opts(args) do
      projects = Project.List.projects(opts)

      {:ok,
       %{
         projects: projects,
         total_projects_count: total_projects_count(projects, opts),
         has_pagination?: Keyword.get(opts, :has_pagination?),
         all_included_slugs: Keyword.get(opts, :included_slugs)
       }}
    end
  end

  @doc ~s"""
  Return a list of slugs described by the selector object.

  See `args_to_opts/1` for description of the argument format.
  """
  def slugs(args) do
    with {:ok, opts} <- args_to_opts(args) do
      slugs = Project.List.projects_slugs(opts)

      {:ok,
       %{
         slugs: slugs,
         total_projects_count: total_projects_count(slugs, opts)
       }}
    end
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

    with {:ok, included_slugs} <- included_slugs_by_filters(filters, filters_combinator),
         included_slugs = intersect_with_base_slugs(included_slugs, base_slugs),
         included_slugs = remove_hidden_slugs(included_slugs),
         {:ok, ordered_slugs} <- ordered_slugs_by_order_by(order_by, included_slugs) do
      opts = [
        has_selector?: not is_nil(args[:selector]),
        has_order?: not is_nil(order_by),
        has_pagination?: not is_nil(pagination),
        pagination: pagination,
        min_volume: Map.get(args, :min_volume),
        included_slugs: included_slugs,
        ordered_slugs: ordered_slugs
      ]

      {:ok, opts}
    end
  end

  # Private functions

  defp intersect_with_base_slugs(slugs, :all), do: slugs
  defp intersect_with_base_slugs(:all, base_slugs), do: base_slugs

  defp intersect_with_base_slugs(slugs, base_slugs) do
    MapSet.intersection(MapSet.new(slugs), MapSet.new(base_slugs))
    |> Enum.to_list()
  end

  defp remove_hidden_slugs(slugs) when is_list(slugs) do
    {:ok, hidden_slugs} =
      Sanbase.Cache.get_or_store(:hidden_projects_slugs_list, fn ->
        {:ok, Project.List.hidden_projects_slugs()}
      end)

    # The &Kernel.--/2 operator removes the first occurrence only. Apply
    # Enum.uniq/1 to make sure there are no duplicates that will be left
    Enum.uniq(slugs) -- hidden_slugs
  end

  defp remove_hidden_slugs(slugs), do: slugs

  defp total_projects_count(list, opts) do
    with true <- Keyword.get(opts, :has_pagination?),
         slugs when is_list(slugs) <- Keyword.get(opts, :included_slugs) do
      length(slugs)
    else
      :all -> Project.List.projects_count()
      :erc20 -> Project.List.erc20_projects_count()
      _ -> length(list)
    end
  end

  defp watchlist_args_to_str(%{watchlist_id: id}), do: "watchlist with id #{id}"
  defp watchlist_args_to_str(%{watchlist_slug: slug}), do: "watchlist with slug #{slug}"

  # TODO: Try reworking it to use an ETS table instead of the process dictionary
  defp detect_cycles!(args) do
    case Process.get(@cycle_detection_key) do
      nil ->
        Process.put(@cycle_detection_key, %{
          iterations_left: 20,
          args_seen_so_far: MapSet.new([args]),
          original_args: args
        })

      %{iterations_left: 0, original_args: original_args} ->
        raise(
          "The base projects nesting of a #{watchlist_args_to_str(original_args)} is too deep."
        )

      %{
        iterations_left: iterations_left,
        args_seen_so_far: args_seen_so_far,
        original_args: original_args
      } ->
        case MapSet.member?(args_seen_so_far, args) do
          true ->
            raise(
              "There is a cycle in the base_projects of #{watchlist_args_to_str(original_args)}."
            )

          false ->
            Process.put(@cycle_detection_key, %{
              iterations_left: iterations_left - 1,
              args_seen_so_far: MapSet.put(args_seen_so_far, args),
              original_args: original_args
            })
        end
    end
  end

  defp base_slugs(:all), do: :all

  defp base_slugs(args_list) do
    Enum.flat_map(args_list, fn args ->
      case get_base_slugs(args) do
        {:ok, slugs} -> slugs
        {:error, error} -> raise(error)
      end
    end)
  end

  defp get_base_slugs(%{watchlist_id: id} = map) do
    detect_cycles!(map)

    id |> Sanbase.UserList.by_id!([]) |> Sanbase.UserList.get_slugs()
  end

  defp get_base_slugs(%{watchlist_slug: slug} = map) do
    detect_cycles!(map)
    slug |> Sanbase.UserList.by_slug() |> Sanbase.UserList.get_slugs()
  end

  defp get_base_slugs(%{slugs: slugs}) when is_list(slugs) do
    {:ok, slugs}
  end

  defp get_base_slugs(data) do
    {:error, "The base slugs argument is invalid: #{inspect(data)}."}
  end

  defp included_slugs_by_filters([], _filters_combinator), do: {:ok, :all}
  defp included_slugs_by_filters([%{name: "erc20"}], _filters_combinator), do: {:ok, :erc20}

  defp included_slugs_by_filters(filters, filters_combinator) when is_list(filters) do
    result =
      filters
      |> Sanbase.Parallel.map(
        fn filter ->
          cache_key = {__MODULE__, :included_slugs_by_filter, filter} |> Sanbase.Cache.hash()
          fun = fn -> slugs_by_filter(filter) end

          case Sanbase.Cache.get_or_store(cache_key, fun) do
            {:ok, slugs} -> MapSet.new(slugs)
            {:error, error} -> {:error, error}
          end
        end,
        timeout: 60_000,
        ordered: false,
        max_concurrency: 3
      )

    case Enum.find(result, &match?({:error, _}, &1)) do
      nil ->
        slugs =
          result
          |> Sanbase.Utils.Transform.combine_mapsets(combinator: filters_combinator)
          |> Enum.to_list()

        {:ok, slugs}

      {:error, error} ->
        {:error, error}
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

  defp slugs_by_filter(%{name: "traded_on_exchanges", args: args}) do
    combinator = Map.get(args, :exchanges_combinator, "and")

    case combinator do
      "and" ->
        Sanbase.Market.slugs_by_exchange_all_of(args[:exchanges])

      "or" ->
        Sanbase.Market.slugs_by_exchange_any_of(args[:exchanges])
    end
  end

  defp ordered_slugs_by_order_by(nil, slugs), do: {:ok, slugs}

  defp ordered_slugs_by_order_by(order_by, slugs) do
    %{metric: metric, from: from, to: to, direction: direction} = order_by
    opts = [aggregation: Map.get(order_by, :aggregation)]

    with {:ok, ordered_slugs} <- Sanbase.Metric.slugs_order(metric, from, to, direction, opts) do
      case slugs do
        :all ->
          {:ok, ordered_slugs}

        :erc20 ->
          slugs_mapset = Project.List.erc20_projects_slugs() |> MapSet.new()
          slugs = Enum.filter(ordered_slugs, &(&1 in slugs_mapset))
          {:ok, slugs}

        ^slugs when is_list(slugs) ->
          slugs_mapset = slugs |> MapSet.new()
          slugs = Enum.filter(ordered_slugs, &(&1 in slugs_mapset))
          {:ok, slugs}
      end
    end
  end
end
