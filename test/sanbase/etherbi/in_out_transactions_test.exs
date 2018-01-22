defmodule Sanbase.Github.EtherbiFundsMovementTest do
  use SanbaseWeb.ConnCase
  use Phoenix.ConnTest

  import Mockery

  alias Sanbase.Model.Project
  alias Sanbase.Etherbi.{Store, Transactions}

  setup do
    %Project{}
    |> Project.changeset(%{name: "Santiment", ticker: "SAN", token_decimals: 18})
    |> Sanbase.Repo.insert!()

    [
      wallet: "0xfe9e8709d3215310075d67e3ed32a380ccf451c8",
      ticker: "SAN",
      timestamp1: 1_514_765_134,
      timestamp2: 1_514_965_515
    ]
  end

  test "fetch in transactions and store them with the token decimal corrections", context do
    transactions = [
      [context.timestamp1, 18_000_000, context.wallet, context.ticker],
      [context.timestamp2, 36_000_000, context.wallet, context.ticker],
    ]

    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body: transactions |> Poison.encode!()
       }}
    )

    datetime1 = DateTime.from_unix!(context.timestamp1)
    datetime2 = DateTime.from_unix!(context.timestamp2)
    token_decimals = %{"SAN" => 18}

    # Inserts into the DB. Must delete it at the end of the test
    Transactions.fetch_and_store(context.wallet, token_decimals)
    {:ok, transactions} = Store.transactions([context.wallet], datetime1, datetime2, "1h", "in")

    assert {datetime1, 1000000, "SAN"} in transactions
    assert {datetime2, 2000000, "SAN"} in transactions

    Store.drop_measurement(context.wallet)
  end
end