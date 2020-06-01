defmodule Sanbase.Clickhouse.ApiCallDataTest do
  use Sanbase.DataCase

  import Sanbase.Factory
  import Sanbase.DateTimeUtils, only: [from_iso8601_to_unix!: 1, from_iso8601!: 1]

  alias Sanbase.Clickhouse.ApiCallData

  setup do
    user = insert(:user)

    [user: user]
  end

  test "clickhouse returns data", context do
    dt1_str = "2019-01-01T00:00:00Z"
    dt2_str = "2019-01-02T00:00:00Z"
    dt3_str = "2019-01-03T00:00:00Z"

    rows = [
      [from_iso8601_to_unix!(dt1_str), 400],
      [from_iso8601_to_unix!(dt2_str), 100],
      [from_iso8601_to_unix!(dt3_str), 200]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        ApiCallData.api_call_history(
          context.user.id,
          from_iso8601!(dt1_str),
          from_iso8601!(dt3_str),
          "1d"
        )

      assert result ==
               {:ok,
                [
                  %{api_calls_count: 400, datetime: from_iso8601!(dt1_str)},
                  %{api_calls_count: 100, datetime: from_iso8601!(dt2_str)},
                  %{api_calls_count: 200, datetime: from_iso8601!(dt3_str)}
                ]}
    end)
  end

  test "clickhouse returns empty list", context do
    dt1_str = "2019-01-01T00:00:00Z"
    dt2_str = "2019-01-03T00:00:00Z"

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: []}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        ApiCallData.api_call_history(
          context.user.id,
          from_iso8601!(dt1_str),
          from_iso8601!(dt2_str),
          "1d"
        )

      assert result == {:ok, []}
    end)
  end

  test "clickhouse returns error", context do
    dt1_str = "2019-01-01T00:00:00Z"
    dt3_str = "2019-01-03T00:00:00Z"

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:error, "Something went wrong"})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        ApiCallData.api_call_history(
          context.user.id,
          from_iso8601!(dt1_str),
          from_iso8601!(dt3_str),
          "1d"
        )

      assert result ==
               {:error, "Something went wrong"}
    end)
  end
end
