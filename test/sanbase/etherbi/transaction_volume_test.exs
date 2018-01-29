defmodule Sanbase.Etherbi.TransactionVolumeTest do
  use SanbaseWeb.ConnCase
  use Phoenix.ConnTest

  import Mockery

  alias Sanbase.Model.Project
  alias Sanbase.Etherbi.TransactionVolume
  alias Sanbase.Etherbi.TransactionVolume.Store

  setup do
    %Project{}
    |> Project.changeset(%{name: "Santiment", ticker: "SAN", token_decimals: 18})
    |> Sanbase.Repo.insert!()

    [
      ticker: "SAN",
      timestamp1: 1_514_765_134,
      timestamp2: 1_514_965_515,
      trx_volume1: 18_000_000_000_000_000_000,
      expected_trx_volume1: 18,
      trx_volume2: 36_000_000_000_000_000_000,
      expected_trx_volume2: 36
    ]
  end

  test "fetch transactionVolume and store it with the token decimal corrections", context do
    token_decimals = %{context.ticker => :math.pow(10, 18)}

    trx_volumes = [
      {DateTime.from_unix!(context.timestamp1), context.volume1},
      {DateTime.from_unix!(context.timestamp2), context.volume2}
    ]

    mock(
      Sanbase.Etherbi.EtherbiApi,
      :get_first_transaction_volume_timestamp,
      DateTime.from_unix(context.timestamp1)
    )

    mock(
      Sanbase.Etherbi.EtherbiApi,
      :get_trx_volume,
      {:ok, trx_volumes}
    )

    datetime1 = DateTime.from_unix!(context.timestamp1)
    datetime2 = DateTime.from_unix!(context.timestamp2)

    # Inserts into the DB. Must delete it at the end of the test
    TransactionVolume.fetch_and_store(context.wallet, token_decimals)
    {:ok, trx_volume} = Store.transactions(context.ticker, datetime1, datetime2, "5m")

    assert {datetime1, context.expected_trx_volume1} in trx_volume
    assert {datetime2, context.expected_trx_volume2} in trx_volume

    Store.drop_measurement(context.ticker)
  end
end
