defmodule Sanbase.Clickhouse.Founders do
  def get_founders(slug \\ nil) do
    query = get_founders_query(slug)

    Sanbase.ClickhouseRepo.query_transform(query, fn [name, project_slug] ->
      %{name: name, slug: project_slug}
    end)
  end

  defp get_founders_query(nil) do
    sql = """
    SELECT name, slug
    FROM founder_metadata
    """

    Sanbase.Clickhouse.Query.new(sql, %{})
  end

  defp get_founders_query(slug) do
    sql = """
    SELECT name, slug
    FROM founder_metadata
    WHERE slug = {{slug}}
    """

    Sanbase.Clickhouse.Query.new(sql, %{slug: slug})
  end
end
