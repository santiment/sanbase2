defmodule Sanbase.Clickhouse.Project do
  def projects_info(slugs) do
    query = projects_info_query(slugs)

    Sanbase.ClickhouseRepo.query_reduce(query, %{}, fn [slug, full, summary], acc ->
      Map.put(acc, slug, %{full: full, summary: summary})
    end)
  end

  defp projects_info_query(slugs) do
    sql = """
    SELECT
        slug,
        info,
        info_summary
    FROM projects_info
    WHERE
      version = ( SELECT max(version) FROM projects_info) AND
      slug IN {{slugs}}
    """

    params = %{
      slugs: slugs
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end
end
