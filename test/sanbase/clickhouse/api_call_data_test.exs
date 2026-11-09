defmodule Sanbase.Clickhouse.ApiCallDataTest do
  use Sanbase.DataCase

  import Sanbase.Factory
  import ExUnit.CaptureLog

  alias Sanbase.Clickhouse.ApiCallData

  setup do
    user = insert(:user)

    [user: user]
  end

  test "clickhouse returns data for api call history", context do
    dt1 = ~U[2019-01-01 00:00:00Z]
    dt2 = ~U[2019-01-02 00:00:00Z]
    dt3 = ~U[2019-01-03 00:00:00Z]

    rows = [
      [DateTime.to_unix(dt1), 400],
      [DateTime.to_unix(dt2), 100],
      [DateTime.to_unix(dt3), 200]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = ApiCallData.api_call_history(context.user.id, dt1, dt3, "1d", :apikey)

      assert result ==
               {:ok,
                [
                  %{api_calls_count: 400, datetime: dt1},
                  %{api_calls_count: 100, datetime: dt2},
                  %{api_calls_count: 200, datetime: dt3}
                ]}
    end)
  end

  test "clickhouse returns data for api call count", context do
    from = ~U[2019-01-01 00:00:00Z]
    to = ~U[2019-01-02 00:00:00Z]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: [[100]]}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert ApiCallData.api_call_count(context.user.id, from, to, :all) == {:ok, 100}
    end)
  end

  test "clickhouse returns per-query usage of a user", context do
    last = ~U[2026-11-01 10:00:00Z]

    rows = [
      ["getMetric|price_usd", 1200, 30, 0, 1230, DateTime.to_unix(last)],
      ["allProjects", 10, 5, 1, 16, DateTime.to_unix(last)]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      from = ~U[2026-10-01 00:00:00Z]

      assert {:ok, [first, second]} = ApiCallData.user_queries_usage(context.user.id, from)

      assert first == %{
               query: "getMetric|price_usd",
               apikey_calls: 1200,
               jwt_calls: 30,
               other_calls: 0,
               total_calls: 1230,
               last_called_at: last
             }

      assert second.query == "allProjects"
      assert second.other_calls == 1
    end)
  end

  test "clickhouse returns empty list", context do
    dt1 = ~U[2019-01-01 00:00:00Z]
    dt2 = ~U[2019-01-03 00:00:00Z]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: []}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = ApiCallData.api_call_history(context.user.id, dt1, dt2, "1d", :all)

      assert result == {:ok, []}
    end)
  end

  test "clickhouse returns error", context do
    dt1 = ~U[2019-01-01 00:00:00Z]
    dt3 = ~U[2019-01-03 00:00:00Z]

    error_msg = "Something went wrong"

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:error, error_msg})
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert capture_log(fn ->
               {:error, error} =
                 ApiCallData.api_call_history(context.user.id, dt1, dt3, "1d", :all)

               assert error =~ "Cannot execute database query."
             end) =~ error_msg
    end)
  end
end
