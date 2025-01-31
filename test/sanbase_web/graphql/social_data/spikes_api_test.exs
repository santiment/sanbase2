defmodule SanbaseWeb.Graphql.SocialDataSpikesApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn}
  end

  test "get metric spike explanations", context do
    rows = [
      [
        DateTime.to_unix(~U[2024-01-01 01:00:00Z]),
        DateTime.to_unix(~U[2024-01-01 02:00:00Z]),
        "Reason 1"
      ],
      [
        DateTime.to_unix(~U[2024-01-02 10:00:00Z]),
        DateTime.to_unix(~U[2024-01-01 12:30:00Z]),
        "Reason 2"
      ]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query =
        get_metric_spike_explanations_query(%{
          metric: "social_dominance_total",
          slug: "ethereum",
          from: ~U[2024-01-01 00:00:00Z],
          to: ~U[2024-01-10 00:00:00Z]
        })

      result =
        context.conn
        |> post("/graphql", query_skeleton(query))
        |> json_response(200)
        |> get_in(["data", "getMetricSpikeExplanations"])

      assert result == [
               %{
                 "explanation" => "Reason 1",
                 "spikeEndDatetime" => "2024-01-01T02:00:00Z",
                 "spikeStartDatetime" => "2024-01-01T01:00:00Z"
               },
               %{
                 "explanation" => "Reason 2",
                 "spikeEndDatetime" => "2024-01-01T12:30:00Z",
                 "spikeStartDatetime" => "2024-01-02T10:00:00Z"
               }
             ]
    end)
  end

  test "get metric spike explanations count", context do
    rows = [
      [DateTime.to_unix(~U[2024-01-01 01:00:00Z]), 10],
      [DateTime.to_unix(~U[2024-01-02 10:00:00Z]), 8]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query =
        get_metric_spike_explanations_count_query(%{
          metric: "social_dominance_total",
          slug: "ethereum",
          from: ~U[2024-01-01 00:00:00Z],
          to: ~U[2024-01-20 00:00:00Z],
          interval: "10d"
        })

      result =
        context.conn
        |> post("/graphql", query_skeleton(query))
        |> json_response(200)
        |> get_in(["data", "getMetricSpikeExplanationsCount"])

      assert result == [
               %{"count" => 10, "datetime" => "2024-01-01T01:00:00Z"},
               %{"count" => 8, "datetime" => "2024-01-02T10:00:00Z"}
             ]
    end)
  end

  test "get metric spike explanations metadata count", context do
    insert(:project, slug: "bitcoin", ticker: "BTC", name: "Bitcoin")

    Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, fn query, _ ->
      if String.contains?(query, "DISTINCT get_metric_name(calculated_on_metric_id)") do
        # That's the internal name in the DB
        {:ok, %{rows: [["social_dominance_1h"]]}}
      else
        {:ok, %{rows: [["bitcoin"]]}}
      end
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = get_metric_spike_explanations_metadata_query()

      result =
        context.conn
        |> post("/graphql", query_skeleton(query))
        |> json_response(200)
        |> get_in(["data", "getMetricSpikeExplanationsMetadata"])

      assert result == [
               %{
                 "availableMetrics" => ["social_dominance_total_1h_moving_average"],
                 "availableProjects" => [%{"slug" => "bitcoin"}],
                 "btcMetrics" => ["social_dominance_total_1h_moving_average"],
                 "dominanceAssets" => [%{"slug" => "bitcoin"}]
               }
             ]
    end)
  end

  defp get_metric_spike_explanations_query(args) do
    """
    {
      getMetricSpikeExplanations(#{map_to_args(args)}) {
        spikeStartDatetime
        spikeEndDatetime
        explanation
      }
    }
    """
  end

  defp get_metric_spike_explanations_count_query(args) do
    """
    {
      getMetricSpikeExplanationsCount(#{map_to_args(args)}) {
        datetime
        count
      }
    }
    """
  end

  defp get_metric_spike_explanations_metadata_query() do
    """
    {
      getMetricSpikeExplanationsMetadata {
        availableProjects { slug }
        availableMetrics
        btcMetrics: availableMetrics(slug: "bitcoin")
        dominanceAssets: availableProjects(metric: "social_dominance_ai_total_1h_moving_average") {
          slug
        }
      }
    }
    """
  end
end
