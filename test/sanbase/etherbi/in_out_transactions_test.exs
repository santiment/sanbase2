defmodule Sanbase.Etherbi.EtherbiFundsMovementTest do
  use SanbaseWeb.ConnCase
  use Phoenix.ConnTest

  import Mockery

  alias Sanbase.Model.Project
  alias Sanbase.Etherbi.Transactions
  alias Sanbase.Etherbi.Transactions.Store

  setup do
    %Project{}
    |> Project.changeset(%{name: "Santiment", ticker: "SAN", token_decimals: 18})
    |> Sanbase.Repo.insert!()

    [
      wallet: "0xfe9e8709d3215310075d67e3ed32a380ccf451c8",
      ticker: "SAN",
      timestamp1: 1_514_765_134,
      timestamp2: 1_514_965_515,
      volume1: 18_000_000_000_000_000_000,
      expected_volume1: 18,
      volume2: 36_000_000_000_000_000_000,
      expected_volume2: 36,
    ]
  end

  test "fetch in transactions and store them with the token decimal corrections", context do
    token_decimals = %{context.ticker => :math.pow(10, 18)}

    transactions = [
      {DateTime.from_unix!(context.timestamp1), context.volume1, context.wallet,
       context.ticker},
      {DateTime.from_unix!(context.timestamp2), context.volume2, context.wallet,
       context.ticker}
    ]

    mock(
      Sanbase.Etherbi.EtherbiApi,
      :get_first_transaction_timestamp,
      DateTime.from_unix(context.timestamp1)
    )

    mock(
      Sanbase.Etherbi.EtherbiApi,
      :get_transactions,
      {:ok, transactions}
    )

    datetime1 = DateTime.from_unix!(context.timestamp1)
    datetime2 = DateTime.from_unix!(context.timestamp2)

    # Inserts into the DB. Must delete it at the end of the test
    Transactions.fetch_and_store_in(context.wallet,   token_decimals)
    {:ok, transactions} = Store.transactions(context.ticker, datetime1, datetime2, "in")

    assert {datetime1, context.expected_volume1, context.wallet} in transactions
    assert {datetime2, context.expected_volume2, context.wallet} in transactions

    Store.drop_measurement(context.ticker)
  end
end