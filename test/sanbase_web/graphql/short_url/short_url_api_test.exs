defmodule SanbaseWeb.Graphql.ShortUrlApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Plug.Conn
  import SanbaseWeb.Graphql.TestHelpers

  test "create and fetch short url", context do
    full_url =
      "/?slug=santiment&from=2020-01-01&to=2020-02-02&interval=10d&isHidden=true&isCartesian=true"

    short_url =
      create_short_url(
        context.conn,
        "/?slug=santiment&from=2020-01-01&to=2020-02-02&interval=10d&isHidden=true&isCartesian=true"
      )

    assert String.length(short_url) < String.length(full_url)

    fetched_full_url = get_full_url(context.conn, short_url)

    assert full_url == fetched_full_url
  end

  defp create_short_url(conn, full_url) do
    mutation = """
    mutation {
      createShortUrl(fullUrl: "#{full_url}")
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
    |> get_in(["data", "createShortUrl"])
  end

  defp get_full_url(conn, short_url) do
    mutation = """
    {
      getFullUrl(shortUrl: "#{short_url}")
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
    |> get_in(["data", "getFullUrl"])
  end
end
