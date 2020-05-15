defmodule SanbaseWeb.Graphql.SocialData.PopularSearchTermApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    [conn: build_conn()]
  end

  test "returns data for an interval", context do
    now = Timex.now() |> DateTime.truncate(:second)
    insert(:popular_search_term, search_term: "btc OR bitcoin", selector_type: "text")
    insert(:popular_search_term, search_term: "santiment", selector_type: "slug")

    from = Timex.shift(now, days: -1)
    to = Timex.shift(now, days: 1)

    result = popular_search_terms(context.conn, from, to)

    assert %{
             "datetime" => DateTime.to_iso8601(now),
             "searchTerm" => "btc OR bitcoin",
             "selectorType" => "text"
           } in result

    assert %{
             "datetime" => DateTime.to_iso8601(now),
             "searchTerm" => "santiment",
             "selectorType" => "slug"
           } in result
  end

  defp popular_search_terms(conn, from, to) do
    query = """
      {
        popularSearchTerms(from: "#{from}" to: "#{to}"){
          datetime
          searchTerm
          selectorType
        }
      }
    """

    conn
    |> post("/graphql", query_skeleton(query, "popularSearchTerms"))
    |> json_response(200)
    |> get_in(["data", "popularSearchTerms"])
  end
end
