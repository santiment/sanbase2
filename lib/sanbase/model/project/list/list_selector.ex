defmodule Sanbase.Model.Project.ListSelector do
  import Sanbase.DateTimeUtils

  alias Sanbase.Model.Project

  def projects(args) do
    opts = args_to_opts(args)

    projects = Project.List.projects(opts)

    {:ok, projects}
  end

  defp args_to_opts(args) do
    filters = get_in(args, [:selector, :filters])
    order_by = get_in(args, [:selector, :order_by])
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
