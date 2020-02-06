defmodule Sanbase.Project.AvailableMetricsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  test "get project's available anomalies" do
    project = insert(:random_erc20_project)
    project2 = insert(:random_erc20_project)

    Sanbase.Mock.prepare_mock2(
      &Sanbase.ClickhouseRepo.query/2,
      {:ok,
       %{
         rows: [
           ["prophet_v1", 1, 1],
           ["prophet_v1", 1, 2],
           ["prophet_v1", 1, 3],
           ["prophet_v1", 2, 3]
         ]
       }}
    )
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.MetadataHelper.asset_id_to_slug_map/0,
      {:ok, %{1 => project.slug, 2 => project2.slug}}
    )
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.MetadataHelper.metric_id_to_metric_name_map/0,
      {:ok, %{1 => "dev_activity", 2 => "daily_active_addresses", 3 => "exchange_balance"}}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = get_available_anomalies(project)
      %{"data" => %{"projectBySlug" => %{"availableAnomalies" => available_metrics}}} = result

      assert available_metrics |> Enum.sort() ==
               [
                 "dev_activity_anomaly",
                 "daily_active_addresses_anomaly",
                 "exchange_balance_anomaly"
               ]
               |> Enum.sort()

      result2 = get_available_anomalies(project2)
      %{"data" => %{"projectBySlug" => %{"availableAnomalies" => available_metrics2}}} = result2

      assert available_metrics2 == ["exchange_balance_anomaly"]
    end)
  end

  defp get_available_anomalies(project) do
    query = """
    {
      projectBySlug(slug: "#{project.slug}"){
        availableAnomalies
      }
    }
    """

    build_conn()
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
