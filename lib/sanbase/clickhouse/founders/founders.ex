defmodule Sanbase.Clickhouse.Founders do
  def get_founders() do
    query = get_founders_query()

    Sanbase.ClickhouseRepo.query_transform(query, fn [name, slug] ->
      %{name: name, slug: slug}
    end)
  end

  defp get_founders_query() do
    sql = """
    SELECT name, slug
    FROM founder_metadata
    """

    Sanbase.Clickhouse.Query.new(sql, %{})
  end
end
