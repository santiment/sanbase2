defmodule SanbaseWeb.Graphql.Clickhouse.ApiAnomalyRawDataTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)

    [
      conn: conn,
      from: ~U[2019-01-01 00:00:00Z],
      to: ~U[2019-01-02 00:00:00Z]
    ]
  end

  test "returns anomalies without anomaly filtering", context do
    %{conn: conn, from: from, to: to} = context

    rows = [
      [
        ~U[2019-01-01 00:00:00Z] |> DateTime.to_unix(),
        "anomaly_mvrv_usd",
        "bitcoin",
        2.4,
        ~s|{"side": "high"}|
      ]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        get_anomalies(conn, :all, :all, from, to)
        |> get_in(["data", "getAnomalies"])

      assert result == [
               %{
                 "datetime" => "2019-01-01T00:00:00Z",
                 "metadata" => %{"side" => "high"},
                 "value" => 2.4,
                 "anomaly" => "anomaly_mvrv_usd",
                 "slug" => "bitcoin",
                 "isHidden" => false
               }
             ]
    end)
  end

  test "returns anomalies with anomaly filtering", context do
    %{conn: conn, from: from, to: to} = context

    rows = [
      [
        ~U[2019-01-01 00:00:00Z] |> DateTime.to_unix(),
        "anomaly_mvrv_usd",
        "bitcoin",
        2.4,
        ~s|{"side": "high"}|
      ]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        get_anomalies(conn, ["anomaly_mvrv_usd"], :all, from, to)
        |> get_in(["data", "getAnomalies"])

      assert result == [
               %{
                 "datetime" => "2019-01-01T00:00:00Z",
                 "metadata" => %{"side" => "high"},
                 "value" => 2.4,
                 "anomaly" => "anomaly_mvrv_usd",
                 "slug" => "bitcoin",
                 "isHidden" => false
               }
             ]
    end)
  end

  test "returns anomalies with selector filtering", context do
    %{conn: conn, from: from, to: to} = context

    insert(:random_erc20_project, slug: "bitcoin")

    rows = [
      [
        ~U[2019-01-01 00:00:00Z] |> DateTime.to_unix(),
        "anomaly_mvrv_usd",
        "bitcoin",
        2.4,
        ~s|{"side": "high"}|
      ]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        get_anomalies(conn, :all, ["bitcoin"], from, to)
        |> get_in(["data", "getAnomalies"])

      assert result == [
               %{
                 "datetime" => "2019-01-01T00:00:00Z",
                 "metadata" => %{"side" => "high"},
                 "value" => 2.4,
                 "anomaly" => "anomaly_mvrv_usd",
                 "slug" => "bitcoin",
                 "isHidden" => false
               }
             ]
    end)
  end

  defp get_anomalies(conn, anomalies, slugs, from, to) do
    query = get_anomalies_query(anomalies, slugs, from, to)

    conn
    |> post("/graphql", query_skeleton(query, "getAnomalies"))
    |> json_response(200)
  end

  defp get_anomalies_query(:all, :all, from, to) do
    """
      {
        getAnomalies(from: "#{from}", to: "#{to}"){
          datetime
          anomaly
          slug
          value
          metadata
          isHidden
        }
      }
    """
  end

  defp get_anomalies_query(anomalies, :all, from, to) do
    anomalies = Enum.map(anomalies, &~s/"#{&1}"/) |> Enum.join(",")

    """
      {
        getAnomalies(anomalies: [#{anomalies}], from: "#{from}", to: "#{to}"){
          datetime
          anomaly
          slug
          value
          metadata
          isHidden
        }
      }
    """
  end

  defp get_anomalies_query(:all, slugs, from, to) do
    slugs_str = Enum.map(slugs, &~s/"#{&1}"/) |> Enum.join(",")

    """
      {
        getAnomalies(from: "#{from}", to: "#{to}", selector: {slugs: [#{slugs_str}]}){
          datetime
          anomaly
          slug
          value
          metadata
          isHidden
        }
      }
    """
  end
end
