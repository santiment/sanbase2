defmodule Sanbase.Clickhouse.GasUsedTest do
  use Sanbase.DataCase
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601_to_unix!: 1, from_iso8601!: 1]

  alias Sanbase.Clickhouse.GasUsed
  require Sanbase.ClickhouseRepo

  setup do
    [
      slug: "ethereum",
      from: from_iso8601!("2019-01-01T00:00:00Z"),
      to: from_iso8601!("2019-01-03T00:00:00Z"),
      interval: "1d"
    ]
  end

  test "when requested interval fits the values interval", context do
    rows = [
      [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), 101],
      [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), 102],
      [from_iso8601_to_unix!("2019-01-03T00:00:00Z"), 103]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = GasUsed.gas_used(context.slug, context.from, context.to, context.interval)

      assert result ==
               {:ok,
                [
                  %{
                    eth_gas_used: 101,
                    gas_used: 101,
                    datetime: from_iso8601!("2019-01-01T00:00:00Z")
                  },
                  %{
                    eth_gas_used: 102,
                    gas_used: 102,
                    datetime: from_iso8601!("2019-01-02T00:00:00Z")
                  },
                  %{
                    eth_gas_used: 103,
                    gas_used: 103,
                    datetime: from_iso8601!("2019-01-03T00:00:00Z")
                  }
                ]}
    end)
  end

  test "when requested interval is not full", context do
    rows = [
      [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), 101],
      [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), 102],
      [from_iso8601_to_unix!("2019-01-03T00:00:00Z"), 103],
      [from_iso8601_to_unix!("2019-01-04T00:00:00Z"), 104]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = GasUsed.gas_used(context.slug, context.from, context.to, "2d")

      assert result ==
               {:ok,
                [
                  %{
                    eth_gas_used: 101,
                    gas_used: 101,
                    datetime: from_iso8601!("2019-01-01T00:00:00Z")
                  },
                  %{
                    eth_gas_used: 102,
                    gas_used: 102,
                    datetime: from_iso8601!("2019-01-02T00:00:00Z")
                  },
                  %{
                    eth_gas_used: 103,
                    gas_used: 103,
                    datetime: from_iso8601!("2019-01-03T00:00:00Z")
                  },
                  %{
                    eth_gas_used: 104,
                    gas_used: 104,
                    datetime: from_iso8601!("2019-01-04T00:00:00Z")
                  }
                ]}
    end)
  end

  test "returns empty array when query returns no rows", context do
    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: []}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = GasUsed.gas_used(context.slug, context.from, context.to, context.interval)

      assert result == {:ok, []}
    end)
  end

  test "returns error when something except ethereum is requested", context do
    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: []}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        GasUsed.gas_used(
          "unsupported",
          context.from,
          context.to,
          context.interval
        )

      assert result == {:error, "Currently only ethereum is supported!"}
    end)
  end
end
