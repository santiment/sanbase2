defmodule Sanbase.Clickhouse.Erc20ShareOfDepositsTest do
  use Sanbase.DataCase
  require Sanbase.ClickhouseRepo
  import Mock
  import Sanbase.Factory
  import Sanbase.DateTimeUtils, only: [from_iso8601_to_unix!: 1, from_iso8601!: 1]
  alias Sanbase.Clickhouse.Erc20ShareOfDeposits

  setup do
    project = insert(:project, %{main_contract_address: "0x123"})

    [
      project: project,
      contract: project.main_contract_address,
      from: from_iso8601!("2019-01-01T00:00:00Z"),
      to: from_iso8601!("2019-01-03T00:00:00Z")
    ]
  end

  test "returns share of deposits from daily active addresses",
       context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), 200_000, 20_000, 10.0],
             [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), 100_000, 10_000, 10.0]
           ]
         }}
      end do
      result =
        Erc20ShareOfDeposits.share_of_deposits(
          context.contract,
          context.from,
          context.to,
          "1d"
        )

      assert result ==
               {:ok,
                [
                  %{
                    datetime: from_iso8601!("2019-01-01T00:00:00Z"),
                    active_addresses: 200_000,
                    active_deposits: 20_000,
                    share_of_deposits: 10.0
                  },
                  %{
                    datetime: from_iso8601!("2019-01-02T00:00:00Z"),
                    active_addresses: 100_000,
                    active_deposits: 10_000,
                    share_of_deposits: 10.0
                  }
                ]}
    end
  end
end
