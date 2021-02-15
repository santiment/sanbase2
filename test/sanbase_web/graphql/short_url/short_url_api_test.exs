defmodule SanbaseWeb.Graphql.ShortUrlApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers

  test "create and fetch short url", context do
    short_url =
      create_short_url(
        context.conn,
        %{
          full_url: "/something",
          data:
            "slug=santiment&from=2020-01-01&to=2020-02-02&interval=10d&isHidden=true&isCartesian=true"
        }
      )

    result = get_full_url(context.conn, short_url)
    full_url = result["fullUrl"]
    data = result["data"]
    assert String.length(short_url) < String.length(full_url)
    assert full_url == "/something"

    assert data ==
             "slug=santiment&from=2020-01-01&to=2020-02-02&interval=10d&isHidden=true&isCartesian=true"
  end

  defp create_short_url(conn, args) do
    mutation = """
    mutation {
      createShortUrl(
        fullUrl: "#{args.full_url}"
        data: "#{args.data}"){
        shortUrl
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
    |> get_in(["data", "createShortUrl", "shortUrl"])
  end

  defp get_full_url(conn, short_url) do
    mutation = """
    {
      getFullUrl(shortUrl: "#{short_url}"){
        fullUrl
        data
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
    |> get_in(["data", "getFullUrl"])
  end
end
