defmodule SanbaseWeb.Graphql.ElasticsearchResolverTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers

  test "elasticsearch successful stats", %{conn: conn} do
    stats =
      elasticsearch_stats_query(conn)
      |> json_response(200)

    assert stats == %{
             "data" => %{
               "elasticsearchStats" => %{
                 "averageDocumentsPerDay" => 33333,
                 "documentsCount" => 1_000_000,
                 "sizeInMegabytes" => 5,
                 "subredditsCount" => 10,
                 "telegramChannelsCount" => 5
               }
             }
           }
  end

  defp elasticsearch_stats_query(conn) do
    query = """
    {
      elasticsearchStats(
        from: "2018-09-01T00:00:00Z",
        to: "2018-10-01T00:00:00Z"){
          documentsCount
          averageDocumentsPerDay
          telegramChannelsCount
          subredditsCount
          sizeInMegabytes
      }
    }
    """

    conn |> post("/graphql", query_skeleton(query, "elasticsearchStats"))
  end
end
