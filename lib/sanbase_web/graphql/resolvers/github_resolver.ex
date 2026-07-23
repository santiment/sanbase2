defmodule SanbaseWeb.Graphql.Resolvers.GithubResolver do
  alias Sanbase.Project
  alias Sanbase.Clickhouse.Github

  @max_slugs 100

  def github_activity_stats(_root, %{slugs: slugs, from: from, to: to}, _resolution) do
    slugs = Enum.uniq(slugs)

    if length(slugs) > @max_slugs do
      {:error, "Cannot fetch github activity stats for more than #{@max_slugs} slugs"}
    else
      projects = Project.List.by_slugs(slugs, preload?: true, preload: [:github_organizations])

      owner_slug_pairs =
        Enum.flat_map(projects, fn project ->
          Enum.map(project.github_organizations, fn org ->
            {String.downcase(org.organization), project.slug}
          end)
        end)

      case Github.github_activity_stats(owner_slug_pairs, from, to) do
        {:ok, rows} ->
          {:ok, add_empty_rows(rows, projects) |> sort_in_input_order(slugs)}

        {:error, error} ->
          {:error, error}
      end
    end
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
