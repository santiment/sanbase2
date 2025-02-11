defmodule Sanbase.Clickhouse.Founders do
  def get_founders(slug_or_slugs \\ []) do
    slugs = List.wrap(slug_or_slugs)
    query = get_founders_query(slugs)

    Sanbase.ClickhouseRepo.query_transform(query, fn [name, project_slug] ->
      %{name: name, slug: project_slug}
    end)
  end

  defp get_founders_query([]) do
    sql = """
    SELECT name, slug
    FROM founder_metadata
    """

    Sanbase.Clickhouse.Query.new(sql, %{})
  end

  defp get_founders_query(slugs) do
    sql = """
    SELECT name, slug
    FROM founder_metadata
    WHERE slug IN ({{slugs}})
    """

    Sanbase.Clickhouse.Query.new(sql, %{slugs: slugs})
  end
end
