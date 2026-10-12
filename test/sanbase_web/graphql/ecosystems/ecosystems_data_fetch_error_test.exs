defmodule SanbaseWeb.Graphql.EcosystemsDataFetchErrorTest do
  # A failed or timed out ecosystem data fetch returns an error, not a silent 0 or []
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias SanbaseWeb.Graphql.EcosystemDataloader

  @error_msg "[47aad229-f5f8-4d4e-b12b-9bd90a7ff0dd] Cannot execute database query."

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    eth_ecosystem = insert(:ecosystem, ecosystem: "ethereum")
    project = insert(:random_erc20_project)
    {:ok, _} = Sanbase.ProjectEcosystemMapping.create(project.id, eth_ecosystem.id)

    %{conn: conn}
  end

  describe "EcosystemDataloader.query/3" do
    @tag capture_log: true
    test "timeseries: a data fetch error does not crash the batch" do
      args = %{
        metric: "ecosystem_dev_activity",
        from: ~U[2024-04-08 00:00:00Z],
        to: ~U[2024-04-11 00:00:00Z],
        interval: "1d",
        aggregation: nil
      }

      Sanbase.Mock.prepare_mock2(
        &Sanbase.Ecosystem.Metric.timeseries_data/6,
        {:error, @error_msg}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        map =
          EcosystemDataloader.query(
            :ecosystem_timeseries_metric_data,
            [{"ethereum", args}],
            nil
          )

        assert {:error, @error_msg} = Map.get(map, {"ethereum", args})
      end)
    end

    @tag capture_log: true
    test "aggregated: a data fetch error does not crash the batch" do
      args = %{
        metric: "ecosystem_github_activity",
        from: ~U[2024-04-08 00:00:00Z],
        to: ~U[2024-04-11 00:00:00Z],
        aggregation: nil
      }

      Sanbase.Mock.prepare_mock2(
        &Sanbase.Ecosystem.Metric.aggregated_timeseries_data/5,
        {:error, @error_msg}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        map =
          EcosystemDataloader.query(
            :ecosystem_aggregated_metric_data,
            [{"ethereum", args}],
            nil
          )

        assert {:error, @error_msg} = Map.get(map, {"ethereum", args})
      end)
    end
  end

  describe "GraphQL API" do
    for {field, metric, fun_name, arity, extra_args} <- [
          {"timeseriesData", "ecosystem_dev_activity", :timeseries_data, 6,
           ~s|interval: "1d"){ datetime value }|},
          {"aggregatedTimeseriesData", "ecosystem_github_activity", :aggregated_timeseries_data,
           5, ")"}
        ],
        {failure, body} <- [
          error: quote(do: {:error, @error_msg}),
          timeout: quote(do: Process.sleep(:infinity))
        ] do
      @tag capture_log: true
      test "#{field} returns an error on a data fetch #{failure}", context do
        query = """
        { getEcosystems(ecosystems: ["ethereum"]){ name
          #{unquote(field)}(metric: "#{unquote(metric)}" from: "2024-04-08T00:00:00Z" to: "2024-04-11T00:00:00Z" #{unquote(extra_args)}
        } }
        """

        mocked_fun = fn unquote_splicing(Enum.map(1..arity, &Macro.var(:"_arg#{&1}", nil))) ->
          unquote(body)
        end

        Sanbase.Mock.prepare_mock(Sanbase.Ecosystem.Metric, unquote(fun_name), mocked_fun)
        |> Sanbase.Mock.prepare_mock2(&Sanbase.Parallel.dataloader_timeout/0, 300)
        |> Sanbase.Mock.run_with_mocks(fn ->
          result =
            context.conn
            |> post("/graphql", query_skeleton(query))
            |> json_response(200)

          assert [%{"message" => message}] = result["errors"]

          assert message ==
                   "Failed to fetch #{unquote(field)} for metric #{unquote(metric)} and ecosystem ethereum"
        end)
      end
    end
  end
end
