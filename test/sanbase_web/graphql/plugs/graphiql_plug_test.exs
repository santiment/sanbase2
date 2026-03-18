defmodule SanbaseWeb.Graphql.GraphiqlPlugTest do
  use SanbaseWeb.ConnCase, async: false

  alias SanbaseWeb.Graphql.GraphiqlPlug

  @moduletag capture_log: true

  # The :api pipeline has `plug :accepts, ["json"]` which rejects HTML requests
  # before they reach GraphiqlPlug. In production, the plug sees HTML requests
  # because Phoenix `forward` passes them before the accepts check takes effect
  # on the rendered response. We test the plug directly for HTML behavior
  # and go through the router for JSON/GraphQL behavior.

  @graphiql_opts GraphiqlPlug.init(
                   json_codec: Jason,
                   schema: SanbaseWeb.Graphql.Schema,
                   interface: :santiment
                 )

  describe "GraphiqlPlug with Accept: text/html" do
    test "returns 200 with HTML page", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "text/html")
        |> GraphiqlPlug.call(@graphiql_opts)

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/html"
    end

    test "HTML contains the graphiql mount point and title", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "text/html")
        |> GraphiqlPlug.call(@graphiql_opts)

      body = conn.resp_body
      assert body =~ ~s(id="graphiql")
      assert body =~ "Santiment GraphiQL"
    end

    test "HTML references JS and CSS assets", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "text/html")
        |> GraphiqlPlug.call(@graphiql_opts)

      body = conn.resp_body
      assert body =~ ~r/src="\/assets\/graphiql[^"]*\.js"/
      assert body =~ ~r/href="\/assets\/graphiql[^"]*\.css"/
    end

    test "sets Content-Security-Policy header", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "text/html")
        |> GraphiqlPlug.call(@graphiql_opts)

      [csp] = get_resp_header(conn, "content-security-policy")
      assert csp =~ "default-src 'self'"
      assert csp =~ "script-src 'self'"
      assert csp =~ "worker-src 'self' blob:"
    end

    test "sets Strict-Transport-Security header", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "text/html")
        |> GraphiqlPlug.call(@graphiql_opts)

      [hsts] = get_resp_header(conn, "strict-transport-security")
      assert hsts =~ "max-age="
    end

    test "sets X-Content-Type-Options header", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "text/html")
        |> GraphiqlPlug.call(@graphiql_opts)

      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    end
  end

  describe "POST /graphiql with JSON (through router)" do
    test "forwards GraphQL queries to Absinthe", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/graphiql", Jason.encode!(%{query: "{ __typename }"}))

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["data"]["__typename"] == "RootQueryType"
    end
  end
end
