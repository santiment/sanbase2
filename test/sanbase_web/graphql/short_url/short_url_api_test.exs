defmodule SanbaseWeb.Graphql.ShortUrlApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn, user: user}
  end

  test "create and fetch short url", context do
    short_url =
      create_short_url(
        context.conn,
        %{
          full_url: "/something",
          data: "slug=santiment&from=2020-01-01&to=2020-02-02&interval=10d&isHidden=true&isCartesian=true"
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

  test "update short url", context do
    short_url =
      insert(:short_url, full_url: "/something", data: "slug=santiment", user: context.user)

    updated_short_url =
      context.conn
      |> update_short_url(%{
        short_url: short_url.short_url,
        full_url: "/new_full_url",
        data: "slug=santiment&from=2020-01-01&to=2020-02-02&interval=10d&isHidden=true&isCartesian=true"
      })
      |> get_in(["data", "updateShortUrl"])

    assert updated_short_url["shortUrl"] == short_url.short_url
    assert updated_short_url["fullUrl"] == "/new_full_url"

    assert updated_short_url["data"] ==
             "slug=santiment&from=2020-01-01&to=2020-02-02&interval=10d&isHidden=true&isCartesian=true"
  end

  test "cannot update anonymously created short url", context do
    short_url = insert(:short_url, full_url: "/something", data: "slug=santiment", user: nil)

    error =
      context.conn
      |> update_short_url(%{
        short_url: short_url.short_url,
        data: "test"
      })
      |> Map.get("errors")
      |> List.first()
      |> Map.get("message")

    assert error =~ "does not exist or belongs to another user and cannot be updated"
  end

  test "cannot update short urls of other users", context do
    user = insert(:user)
    short_url = insert(:short_url, full_url: "/something", data: "slug=santiment", user: user)

    error =
      context.conn
      |> update_short_url(%{
        short_url: short_url.short_url,
        data: "test"
      })
      |> Map.get("errors")
      |> List.first()
      |> Map.get("message")

    assert error =~ "does not exist or belongs to another user and cannot be updated"
  end

  defp create_short_url(conn, args) do
    mutation = """
    mutation {
      createShortUrl(
        fullUrl: "#{args.full_url}"
        data: "#{args.data}"){
          shortUrl
          data
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

  defp update_short_url(conn, args) do
    mutation = """
    mutation {
      updateShortUrl(
        shortUrl: "#{args[:short_url]}"
        fullUrl: "#{args[:full_url]}"
        data: "#{args[:data]}"){
          data
          shortUrl
          fullUrl
        }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end
end
