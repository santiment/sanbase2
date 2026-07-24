defmodule SanbaseWeb.Graphql.Resolvers.GithubResolver do
  alias Sanbase.Project
  alias Sanbase.Clickhouse.Github

  @max_projects 100

  # The ordering can contain slugs that cannot appear in the result - slugs
  # without a project in our database, slugs of hidden projects or of
  # projects without github organizations. The ordered slugs are checked
  # against the database in batches of topN * overshoot factor slugs, so in
  # the common case a single check fills all topN spots.
  @overshoot_factor 2

  def github_activity_stats(_root, %{selector: selector, from: from, to: to}, _resolution) do
    slugs = Map.get(selector, :slugs)
    top_n = Map.get(selector, :top_n)
    sort_by = Map.get(selector, :sort_by)

    cond do
      is_list(slugs) and is_integer(top_n) ->
        {:error, "The selector must have exactly one of the fields slugs and topN, not both"}

      is_list(slugs) ->
        slugs_stats(slugs, sort_by, from, to)

      is_integer(top_n) ->
        top_n_stats(top_n, sort_by, from, to)

      true ->
        {:error, "The selector must have exactly one of the fields slugs and topN"}
    end
  end

  defp slugs_stats(slugs, sort_by, from, to) do
    slugs = Enum.uniq(slugs)

    if length(slugs) > @max_projects do
      {:error, "Cannot fetch github activity stats for more than #{@max_projects} slugs"}
    else
      projects = Project.List.by_slugs(slugs, preload?: true, preload: [:github_organizations])

      owner_slug_pairs =
        Enum.flat_map(projects, fn project ->
          Enum.map(project.github_organizations, fn org ->
            {String.downcase(org.organization), project.slug}
          end)
        end)

      case Github.github_activity_stats(owner_slug_pairs, from, to, order_by: sort_by) do
        {:ok, rows} ->
          rows = add_empty_rows(rows, projects)
          # Without an explicit sortBy the result is in the same order as the
          # input slugs. With it the rows with data are already sorted by
          # ClickHouse and the zero rows are appended at the end.
          rows = if is_nil(sort_by), do: sort_in_input_order(rows, slugs), else: rows

          {:ok, rows}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  # The precomputed per-slug metrics are used to get the top N slugs, which
  # is much cheaper than ranking the projects from the raw github events.
  # The stats for the top slugs are then computed the same way as when the
  # slugs are provided explicitly.
  @sort_by_ranking_metric %{
    dev_activity: "dev_activity_1d",
    github_activity: "github_activity_1d"
  }

  defp top_n_stats(top_n, sort_by, from, to) do
    cond do
      top_n < 1 or top_n > @max_projects ->
        {:error, "topN must be between 1 and #{@max_projects}"}

      is_nil(sort_by) ->
        {:error, "The selector must have the sortBy field when topN is used"}

      true ->
        metric = Map.fetch!(@sort_by_ranking_metric, sort_by)

        # The ordering must be computed with the current day realtime data
        # included, so the incomplete data is not cut off
        opts = [include_incomplete_data: true]

        with {:ok, slugs} <- Sanbase.Metric.slugs_order(metric, from, to, :desc, opts) do
          slugs
          |> take_top_n(top_n)
          |> slugs_stats(sort_by, from, to)
        end
    end
  end

  # Take the first top_n slugs of projects that exist, are not hidden and
  # have github organizations. The ranking is checked against the database
  # in batches of top_n * overshoot factor slugs, digging deeper into it
  # until the top_n spots are filled or the ranking is exhausted. The order
  # of the slugs is preserved.
  defp take_top_n(slugs, top_n) do
    slugs
    |> Stream.chunk_every(top_n * @overshoot_factor)
    |> Enum.reduce_while([], fn chunk, acc ->
      acc = acc ++ remove_hidden_and_without_github_orgs(chunk)

      if length(acc) >= top_n, do: {:halt, acc}, else: {:cont, acc}
    end)
    |> Enum.take(top_n)
  end

  # Keep only the slugs of projects that exist, are not hidden and have
  # github organizations. The order of the slugs is preserved.
  defp remove_hidden_and_without_github_orgs(slugs) do
    slugs_with_github_orgs =
      Project.List.by_slugs(slugs,
        include_hidden: false,
        preload?: true,
        preload: [:github_organizations]
      )
      |> Enum.filter(fn project -> project.github_organizations != [] end)
      |> MapSet.new(& &1.slug)

    Enum.filter(slugs, &MapSet.member?(slugs_with_github_orgs, &1))
  end

  # Projects without github organizations or without any activity in the
  # time period are not present in the ClickHouse result. Return them with
  # zero values so every requested project has a row.
  defp add_empty_rows(rows, projects) do
    slugs_with_data = MapSet.new(rows, & &1.slug)

    empty_rows =
      projects
      |> Enum.reject(&MapSet.member?(slugs_with_data, &1.slug))
      |> Enum.map(
        &%{
          slug: &1.slug,
          dev_activity: 0,
          github_activity: 0,
          dev_activity_contributors_count: 0,
          github_activity_contributors_count: 0,
          bot_dev_activity: 0,
          bot_github_activity: 0,
          bot_contributors_count: 0
        }
      )

    rows ++ empty_rows
  end

  defp sort_in_input_order(rows, slugs) do
    position_map = slugs |> Enum.with_index() |> Map.new()

    Enum.sort_by(rows, &Map.get(position_map, &1.slug))
  end
end
