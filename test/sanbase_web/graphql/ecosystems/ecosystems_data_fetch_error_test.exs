defmodule SanbaseWeb.Graphql.EcosystemsDataFetchErrorTest do
  # A failed or timed out ecosystem data fetch returns an error, not a silent 0 or []
  use SanbaseWeb.ConnCase,
    async: false,
    parameterize:
      for(
        field <- [
          %{
            field: "timeseriesData",
            metric: "ecosystem_dev_activity",
            fun: :timeseries_data,
            arity: 6,
            rest: ~s|interval: "1d"){ datetime value }|
          },
          %{
            field: "aggregatedTimeseriesData",
            metric: "ecosystem_github_activity",
            fun: :aggregated_timeseries_data,
            arity: 5,
            rest: ")"
          }
        ],
        failure <- [:error, :timeout],
        do: Map.put(field, :failure, failure)
      )

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    eth_ecosystem = insert(:ecosystem, ecosystem: "ethereum")
    project = insert(:random_erc20_project)
    {:ok, _} = Sanbase.ProjectEcosystemMapping.create(project.id, eth_ecosystem.id)

    %{conn: conn}
  end

  @tag capture_log: true
  test "a failed data fetch returns an error", context do
    query = """
    { getEcosystems(ecosystems: ["ethereum"]){ name
      #{context.field}(metric: "#{context.metric}" from: "2024-04-08T00:00:00Z" to: "2024-04-11T00:00:00Z" #{context.rest}
    } }
    """

    fetch = Sanbase.Mock.wrap_consecutives([failing_fetch(context.failure)], arity: context.arity)

    Sanbase.Mock.prepare_mock(Sanbase.Ecosystem.Metric, context.fun, fetch)
    |> Sanbase.Mock.prepare_mock2(&Sanbase.Parallel.dataloader_timeout/0, 300)
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        context.conn
        |> post("/graphql", query_skeleton(query))
        |> json_response(200)

      assert [%{"message" => message}] = result["errors"]

      assert message ==
               "Failed to fetch #{context.field} for metric #{context.metric} and ecosystem ethereum"
    end)
  end

  defp failing_fetch(:error), do: fn -> {:error, "Cannot execute database query."} end
  defp failing_fetch(:timeout), do: fn -> Process.sleep(:infinity) end
end
