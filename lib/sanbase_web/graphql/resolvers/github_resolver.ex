defmodule SanbaseWeb.Graphql.Resolvers.GithubResolver do
  alias Sanbase.Clickhouse.Github
  alias Sanbase.Project

  @max_projects 100

  # The precomputed per-slug metrics used to rank the projects when topN is
  # used. Ranking by them is much cheaper than ranking by the raw github events
  @sort_by_ranking_metric %{
    dev_activity: "dev_activity_1d",
    github_activity: "github_activity_1d"
  }

  # The ranking contains slugs that cannot appear in the result - slugs without
  # a project in the database, slugs of hidden projects and slugs of projects
  # without github organizations. It is checked against the database in batches
  # that are big enough to fill all topN spots with a single check in the
  # common case.
  @ranking_batch_size @max_projects * 2

  def github_activity_stats(_root, %{selector: selector, from: from, to: to}, _resolution) do
    sort_by = Map.get(selector, :sort_by)

    case {Map.get(selector, :slugs), Map.get(selector, :top_n)} do
      {slugs, nil} when is_list(slugs) ->
        slugs_stats(slugs, sort_by, from, to)

      {nil, top_n} when is_integer(top_n) ->
        top_n_stats(top_n, sort_by, from, to)

      {nil, nil} ->
        {:error, "The selector must have exactly one of the fields slugs and topN"}

      _ ->
        {:error, "The selector must have exactly one of the fields slugs and topN, not both"}
    end
  end

  defp slugs_stats(slugs, sort_by, from, to) do
    slugs = Enum.uniq(slugs)

    if length(slugs) > @max_projects do
      {:error, "Cannot fetch github activity stats for more than #{@max_projects} slugs"}
    else
      slugs
      |> fetch_projects()
      |> stats(sort_by, from, to)
    end
  end

  defp top_n_stats(top_n, sort_by, from, to) do
    cond do
      top_n < 1 or top_n > @max_projects ->
        {:error, "topN must be between 1 and #{@max_projects}"}

      is_nil(sort_by) ->
        {:error, "The selector must have the sortBy field when topN is used"}

      true ->
        metric = Map.fetch!(@sort_by_ranking_metric, sort_by)

        with {:ok, ranked_slugs} <- Sanbase.Metric.slugs_order(metric, from, to, :desc) do
          ranked_slugs
          |> top_n_projects(top_n)
          |> stats(sort_by, from, to)
        end
    end
  end

  # Take the projects of the first top_n ranked slugs that can appear in the
  # result, digging deeper into the ranking until the topN spots are filled or
  # the ranking is exhausted. The ranking order is preserved.
  defp top_n_projects(ranked_slugs, top_n) do
    ranked_slugs
    |> Stream.chunk_every(@ranking_batch_size)
    |> Enum.reduce_while([], fn slugs_batch, projects ->
      batch_projects =
        slugs_batch
        |> fetch_projects()
        |> Enum.reject(&(&1.github_organizations == []))

      projects = projects ++ batch_projects

      if length(projects) >= top_n, do: {:halt, projects}, else: {:cont, projects}
    end)
    |> Enum.take(top_n)
  end

  # Slugs without a project and slugs of hidden projects are dropped. The
  # projects are returned in the same order as the input slugs.
  defp fetch_projects(slugs) do
    Project.List.by_slugs(slugs, preload?: true, preload: [:github_organizations])
  end

  defp stats(projects, sort_by, from, to) do
    owner_slug_pairs =
      for project <- projects, organization <- project.github_organizations do
        {organization.organization, project.slug}
      end

    with {:ok, rows} <- Github.github_activity_stats(owner_slug_pairs, from, to) do
      stats_by_slug = Map.new(rows, &{&1.slug, &1})

      # Projects without github organizations or without any activity in the
      # time period have no row in the result, so they get zero values
      stats =
        projects
        |> Enum.map(fn %{slug: slug} ->
          Map.get_lazy(stats_by_slug, slug, fn -> Github.empty_activity_stats(slug) end)
        end)
        |> sort_stats(sort_by)

      {:ok, stats}
    end
  end

  # Without a sortBy the stats are in the same order as the projects - the order
  # of the input slugs, or the ranking order when topN is used.
  defp sort_stats(stats, nil), do: stats
  defp sort_stats(stats, sort_by), do: Enum.sort_by(stats, &Map.fetch!(&1, sort_by), :desc)
end
