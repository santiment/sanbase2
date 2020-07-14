defmodule Sanbase.Model.Project.ListSelector do
  import Norm
  import Sanbase.DateTimeUtils

  alias Sanbase.Model.Project

  def valid_selector?(args) do
    args = Sanbase.MapUtils.atomize_keys(args)

    order_by_schema =
      schema(%{
        metric: spec(is_binary()),
        from: spec(&match?(%DateTime{}, &1)),
        to: spec(&match?(%DateTime{}, &1)),
        direction: spec(is_atom())
      })

    pagination_schema =
      schema(%{
        page: spec(&(is_integer(&1) and &1 > 0)),
        page_size: spec(&(is_integer(&1) and &1 > 0))
      })

    filters = args_to_filters(args)
    order_by = args_to_order_by(args) || %{}
    pagination = args_to_pagination(args) || %{}

    with true <- check_filters(filters),
         true <- valid_filters_combinator?(args),
         {:ok, _} <- conform(order_by, order_by_schema),
         {:ok, _} <- conform(pagination, pagination_schema) do
      true
    end
  end

  defp check_filters(filters) do
    with true <- filters_structure_valid?(filters),
         true <- filters_metrics_valid?(filters) do
      true
    else
      error -> error
    end
  end

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

    filters = args_to_filters(args)
    order_by = args_to_order_by(args)
    pagination = args_to_pagination(args)
    filters_combinator = args_to_filters_combinator(args)

    included_slugs = filters |> included_slugs_by_filters(filters_combinator)
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

  defp total_projects_count(list, opts) do
    with true <- Keyword.get(opts, :has_pagination?),
         slugs when is_list(slugs) <- Keyword.get(opts, :included_slugs) do
      length(slugs)
    else
      _ -> length(list)
    end
  end

  defp filters_metrics_valid?(filters) do
    Enum.find(filters, fn %{metric: metric} ->
      not Sanbase.Metric.has_metric?(metric)
    end)
    |> case do
      nil -> true
      metric -> {:error, "The metric #{metric} is mistyped or not supported."}
    end
  end

  defp filters_structure_valid?(filters) do
    filter_schema =
      schema(%{
        metric: spec(is_binary()),
        from: spec(&match?(%DateTime{}, &1)),
        to: spec(&match?(%DateTime{}, &1)),
        operator: spec(is_atom()),
        threshold: spec(is_number()),
        aggregation: spec(is_atom())
      })

    Enum.map(filters, &conform(&1, filter_schema))
    |> Enum.find(&match?({:error, _}, &1))
    |> case do
      nil ->
        Enum.map(
          filters,
          &([:metric, :from, :to, :operator, :threshold, :aggregation] -- Map.keys(&1))
        )
        |> Enum.find(&(&1 != []))
        |> case do
          nil -> true
          fields -> {:error, "A filter has missing fields: #{inspect(fields)}."}
        end

      error ->
        error
    end
  end

  defp valid_filters_combinator?(args) do
    filters_combinator =
      (get_in(args, [:selector, :filters_combinator]) || "and")
      |> to_string()
      |> String.downcase()

    case filters_combinator in ["and", "or"] do
      true ->
        true

      false ->
        {:error,
         """
         Unsupported filter combinator #{inspect(filters_combinator)}.
         Supported filter combinators are 'and' and 'or'
         """}
    end
  end

  defp args_to_filters_combinator(args) do
    (get_in(args, [:selector, :filters_combinator]) || "and")
    |> to_string()
    |> String.downcase()
  end

  defp args_to_filters(args) do
    (get_in(args, [:selector, :filters]) || [])
    |> Enum.map(&transform_from_to/1)
    |> Enum.map(&update_dynamic_datetimes/1)
    |> Enum.map(&atomize_values/1)
  end

  defp args_to_order_by(args) do
    get_in(args, [:selector, :order_by])
    |> transform_from_to()
    |> update_dynamic_datetimes()
    |> atomize_values()
  end

  defp args_to_pagination(args) do
    get_in(args, [:selector, :pagination])
  end

  defp atomize_values(nil), do: nil

  defp atomize_values(map) do
    {to_atomize, rest} = Map.split(map, [:operator, :aggregation, :direction])

    to_atomize
    |> Enum.into(%{}, fn {k, v} ->
      v = if is_binary(v), do: String.to_existing_atom(v), else: v
      {k, v}
    end)
    |> Map.merge(rest)
  end

  defp transform_from_to(%{from: from, to: to} = map) do
    %{
      map
      | from: if(is_binary(from), do: from_iso8601!(from), else: from),
        to: if(is_binary(to), do: from_iso8601!(to), else: to)
    }
  end

  defp transform_from_to(map), do: map

  defp update_dynamic_datetimes(nil), do: nil

  defp update_dynamic_datetimes(filter) do
    dynamic_from = Map.get(filter, :dynamic_from)
    dynamic_to = Map.get(filter, :dynamic_to)

    case {dynamic_from, dynamic_to} do
      {nil, nil} ->
        filter

      {nil, _} ->
        {:error, "Cannot use 'dynamic_to' without 'dynamic_from'."}

      {_, nil} ->
        {:error, "Cannot use 'dynamic_from' without 'dynamic_to'."}

      _ ->
        now = Timex.now()

        from = Timex.shift(now, seconds: -Sanbase.DateTimeUtils.str_to_sec(dynamic_from))

        to =
          case dynamic_to do
            "now" ->
              now

            _ ->
              Timex.shift(now, seconds: -Sanbase.DateTimeUtils.str_to_sec(dynamic_to))
          end

        filter
        |> Map.put(:from, from)
        |> Map.put(:to, to)
    end
  end

  defp included_slugs_by_filters([], _filters_combinator), do: :all

  defp included_slugs_by_filters(filters, filters_combinator) when is_list(filters) do
    slug_mapsets =
      filters
      |> Sanbase.Parallel.map(
        fn filter ->
          cache_key =
            {:included_slugs_by_filters,
             %{filter | from: round_datetime(filter.from), to: round_datetime(filter.to)}}
            |> Sanbase.Cache.hash()

          {:ok, slugs} =
            Sanbase.Cache.get_or_store(cache_key, fn ->
              Sanbase.Metric.slugs_by_filter(
                filter.metric,
                filter.from,
                filter.to,
                filter.operator,
                filter.threshold,
                filter.aggregation
              )
            end)

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
