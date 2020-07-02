defmodule Sanbase.Model.Project.ListSelector do
  import Sanbase.DateTimeUtils

  alias Sanbase.Model.Project

  @doc ~s"""
  Return a list of projects described by the selector object.

  See `args_to_opts/1` for description of the argument format.
  """
  def projects(args) do
    opts = args_to_opts(args)

    {:ok, Project.List.projects(opts)}
  end

  def slugs(args) do
    opts = args_to_opts(args)
    {:ok, Project.List.projects_slugs()}
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
    filters =
      (get_in(args, [:selector, :filters]) || [])
      |> Enum.map(&transform_from_to/1)
      |> Enum.map(&update_dynamic_datetimes/1)
      |> Enum.map(&atomize_values/1)

    order_by =
      get_in(args, [:selector, :order_by])
      |> transform_from_to()
      |> update_dynamic_datetimes()
      |> atomize_values()

    pagination = get_in(args, [:selector, :pagination])

    included_slugs = filters |> included_slugs_by_filters()
    ordered_slugs = order_by |> ordered_slugs_by_order_by(included_slugs)

    [
      has_selector?: not is_nil(args[:selector]),
      has_order?: not is_nil(order_by),
      has_filters?: not is_nil(filters),
      has_pagination?: not is_nil(pagination),
      pagination: pagination,
      min_volume: Map.get(args, :min_volume),
      included_slugs: included_slugs,
      ordered_slugs: ordered_slugs
    ]
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

  defp included_slugs_by_filters(nil), do: :all
  defp included_slugs_by_filters([]), do: :all

  defp included_slugs_by_filters(filters) when is_list(filters) do
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
    |> Enum.reduce(&MapSet.intersection(&1, &2))
    |> Enum.to_list()
  end

  defp ordered_slugs_by_order_by(nil, slugs), do: slugs

  defp ordered_slugs_by_order_by(order_by, slugs) do
    %{metric: metric, from: from, to: to, direction: direction} = order_by
    aggregation = Map.get(order_by, :aggregation)

    {:ok, ordered_slugs} = Sanbase.Metric.slugs_order(metric, from, to, direction, aggregation)

    case slugs do
      :all ->
        ordered_slugs

      ^slugs when is_list(slugs) ->
        slugs_mapset = slugs |> MapSet.new()
        Enum.filter(ordered_slugs, &(&1 in slugs_mapset))
    end
  end
end
