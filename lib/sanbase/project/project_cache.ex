defmodule Sanbase.Project.ProjectCache do
  @moduledoc """
  In-memory cache for project data with fuzzy search functionality.
  Caches all projects (name, ticker, slug) to avoid DB queries for autocomplete.
  """

  import Ecto.Query
  alias Sanbase.Cache
  alias Sanbase.Project

  @cache_key "project_search_data"
  # 1 hour in seconds
  @cache_ttl 3600

  @doc """
  Search for projects using fuzzy matching on name, ticker, and slug.
  Returns list of tickers sorted by relevance score.
  """
  def search_projects(query, limit \\ 10) when is_binary(query) do
    query = String.trim(query)

    if String.length(query) < 2 do
      []
    else
      project_data = get_cached_projects()
      search_with_fuzzy_matching(project_data, query, limit)
    end
  end

  @doc """
  Get all cached project data, loading from DB if cache is empty or expired.
  """
  def get_cached_projects do
    Cache.get_or_store(
      Cache.name(),
      {@cache_key, @cache_ttl},
      &load_projects_from_db/0
    )
  end

  @doc """
  Clear the project cache, forcing a reload on next access.
  """
  def clear_cache do
    Cache.clear(Cache.name(), @cache_key)
  end

  defp load_projects_from_db do
    from(p in Project,
      where: not is_nil(p.ticker) and not is_nil(p.name) and not is_nil(p.slug),
      select: %{
        name: p.name,
        ticker: p.ticker,
        slug: p.slug
      }
    )
    |> Sanbase.Repo.all()
  end

  defp search_with_fuzzy_matching(projects, query, limit) do
    query_upper = String.upcase(query)

    projects
    |> Enum.map(&score_project(&1, query, query_upper))
    |> Enum.filter(fn {_project, score} -> score > 0 end)
    |> Enum.sort_by(fn {_project, score} -> score end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {project, _score} -> project.ticker end)
  end

  defp score_project(project, query, query_upper) do
    # Calculate relevance scores for each field
    # Highest weight
    ticker_score = calculate_field_score(project.ticker, query_upper, 3.0)
    # Medium weight
    name_score = calculate_field_score(project.name, query, 2.0)
    # Lowest weight
    slug_score = calculate_field_score(project.slug, query, 1.0)

    max_score = max(ticker_score, max(name_score, slug_score))
    {project, max_score}
  end

  defp calculate_field_score(field, query, weight) when is_binary(field) do
    field_upper = String.upcase(field)
    query_upper = String.upcase(query)

    cond do
      # Exact match gets highest score
      field_upper == query_upper ->
        100.0 * weight

      # Starts with query gets high score
      String.starts_with?(field_upper, query_upper) ->
        80.0 * weight

      # Contains query gets medium score
      String.contains?(field_upper, query_upper) ->
        60.0 * weight

      # Fuzzy similarity only for queries 4+ characters
      String.length(query) >= 4 ->
        similarity = FuzzyCompare.similarity(query_upper, field_upper)
        if similarity > 0.8, do: similarity * 40.0 * weight, else: 0.0

      # No fuzzy matching for short queries
      true ->
        0.0
    end
  end

  defp calculate_field_score(_field, _query, _weight), do: 0.0
end
