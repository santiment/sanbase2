defmodule SanbaseWeb.Graphql.Resolvers.ProjectListResolver do
  require Logger

  import Sanbase.DateTimeUtils

  alias Sanbase.Model.Project

  @spec all_projects(any, map, any) :: {:ok, any}
  def all_projects(_parent, args, _resolution) do
    page = Map.get(args, :page)
    page_size = Map.get(args, :page_size)
    opts = args_to_opts(args)

    projects =
      if page_arguments_valid?(page, page_size) do
        Project.List.projects_page(page, page_size, opts)
      else
        Project.List.projects(opts)
        # |> post_fetch_projects_processing(opts)
      end

    {:ok, projects}
  end

  def all_erc20_projects(_root, args, _resolution) do
    page = Map.get(args, :page)
    page_size = Map.get(args, :page_size)
    opts = args_to_opts(args)

    erc20_projects =
      if page_arguments_valid?(page, page_size) do
        Project.List.erc20_projects_page(page, page_size, opts)
      else
        Project.List.erc20_projects(opts)
        # |> post_fetch_projects_processing(opts)
      end

    {:ok, erc20_projects}
  end

  def all_currency_projects(_root, args, _resolution) do
    page = Map.get(args, :page)
    page_size = Map.get(args, :page_size)
    opts = args_to_opts(args)

    currency_projects =
      if page_arguments_valid?(page, page_size) do
        Project.List.currency_projects_page(page, page_size, opts)
      else
        Project.List.currency_projects(opts)
        # |> post_fetch_projects_processing(opts)
      end

    {:ok, currency_projects}
  end

  def all_projects_by_function(_root, %{function: function}, _resolution) do
    with {:ok, function} <- Sanbase.WatchlistFunction.cast(function),
         projects when is_list(projects) <- Sanbase.WatchlistFunction.evaluate(function) do
      {:ok, projects}
    end
  end

  def all_projects_by_ticker(_root, %{ticker: ticker}, _resolution) do
    {:ok, Project.List.projects_by_ticker(ticker)}
  end

  def projects_count(_root, args, _resolution) do
    opts = args_to_opts(args)

    {:ok,
     %{
       erc20_projects_count: Project.List.erc20_projects_count(opts),
       currency_projects_count: Project.List.currency_projects_count(opts),
       projects_count: Project.List.projects_count(opts)
     }}
  end

  # Private functions

  defp page_arguments_valid?(page, page_size) when is_integer(page) and is_integer(page_size) do
    page > 0 and page_size > 0
  end

  defp page_arguments_valid?(_, _), do: false

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
          |> :erlang.phash2()

        {:ok, slugs} =
          Sanbase.Cache.get_or_store(cache_key, fn ->
            Sanbase.Metric.slugs_by_filter(
              filter.metric,
              filter.from,
              filter.to,
              filter.aggregation,
              filter.operator,
              filter.threshold
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
    %{metric: metric, from: from, to: to, aggregation: aggregation, direction: direction} =
      order_by

    {:ok, ordered_slugs} = Sanbase.Metric.slugs_order(metric, from, to, aggregation, direction)

    case slugs do
      :all ->
        ordered_slugs

      ^slugs when is_list(slugs) ->
        slugs_mapset = slugs |> MapSet.new()
        Enum.filter(ordered_slugs, &(&1 in slugs_mapset))
    end
  end
end
