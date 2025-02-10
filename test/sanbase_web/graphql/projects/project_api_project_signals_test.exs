defmodule SanbaseWeb.Graphql.Clickhouse.ProjectApiProjectSignalsTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Signal

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)

    insert(:random_project, slug: "multi-collateral-dai")

    [
      conn: conn,
      slug: "multi-collateral-dai"
    ]
  end

  test "Fetch available anomalies for project with slug", context do
    %{conn: conn, slug: slug} = context

    (&Signal.available_signals/1)
    |> Sanbase.Mock.prepare_mock2({:ok, ["dai_mint"]})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        conn
        |> get_available_signals(slug)
        |> get_in(["data", "projectBySlug", "availableSignals"])

      assert result === ["dai_mint"]
    end)
  end

  # Private functions

  defp get_available_signals(conn, slug) do
    query = get_available_signals_query(slug)

    conn
    |> post("/graphql", query_skeleton(query, "projectBySlug"))
    |> json_response(200)
  end

  defp get_available_signals_query(slug) do
    """
    {
      projectBySlug(slug: "#{slug}") {
        availableSignals
      }
    }
    """
  end
end
