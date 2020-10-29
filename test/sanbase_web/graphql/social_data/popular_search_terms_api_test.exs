defmodule SanbaseWeb.Graphql.SocialData.PopularSearchTermApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  test "returns data for an interval", context do
    now = Timex.now() |> DateTime.truncate(:second)
    yesterday = Timex.shift(now, days: -1)

    insert(:popular_search_term,
      title: "Title",
      search_term: "btc OR bitcoin",
      selector_type: "text",
      datetime: yesterday,
      options: %{interval: "1h", width: "60d"}
    )

    insert(:popular_search_term,
      title: "Title 2",
      search_term: "santiment",
      selector_type: "slug",
      datetime: now,
      options: %{interval: "1h", width: "60d"}
    )

    from = Timex.shift(now, days: -1)
    to = Timex.shift(now, days: 1)

    result = popular_search_terms(context.conn, from, to)

    assert %{
             "title" => "Title",
             "datetime" => DateTime.to_iso8601(yesterday),
             "searchTerm" => "btc OR bitcoin",
             "selectorType" => "text",
             "options" => %{"interval" => "1h", "width" => "60d"}
           } in result

    assert %{
             "title" => "Title 2",
             "datetime" => DateTime.to_iso8601(now),
             "searchTerm" => "santiment",
             "selectorType" => "slug",
             "options" => %{"interval" => "1h", "width" => "60d"}
           } in result
  end

  defp popular_search_terms(conn, from, to) do
    query = """
      {
        popularSearchTerms(from: "#{from}" to: "#{to}"){
          title
          datetime
          searchTerm
          selectorType
          options
        }
      }
    """

    execute_query(conn, query, "popularSearchTerms")
  end
end
