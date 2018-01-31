defmodule Sanbase.Etherbi.BurnRateTest do
  use SanbaseWeb.ConnCase
  use Phoenix.ConnTest

  import Mockery

  alias Sanbase.Model.Project
  alias Sanbase.Etherbi.BurnRate
  alias Sanbase.Etherbi.BurnRate.Store

  setup do
    ticker = "SAN"

    Store.create_db()
    Store.drop_measurement(ticker)

    %Project{}
    |> Project.changeset(%{name: "Santiment", ticker: ticker, token_decimals: 18})
    |> Sanbase.Repo.insert!()

    [
      ticker: ticker,
      timestamp1: 1_514_765_100,
      timestamp2: 1_514_965_500,
      burn_rate1: 18_000_000_000_000_000_000,
      expected_burn_rate1: 18,
      burn_rate2: 36_000_000_000_000_000_000,
      expected_burn_rate2: 36
    ]
  end

  test "fetch burn rate and store it with the token decimal corrections", context do
    token_decimals = %{context.ticker => :math.pow(10, 18)}

    burn_rates = [
      {DateTime.from_unix!(context.timestamp1), context.burn_rate1},
      {DateTime.from_unix!(context.timestamp2), context.burn_rate2}
    ]

    mock(
      Sanbase.Etherbi.EtherbiApi,
      :get_first_burn_rate_timestamp,
      DateTime.from_unix(context.timestamp1)
    )

    mock(
      Sanbase.Etherbi.EtherbiApi,
      :get_burn_rate,
      {:ok, burn_rates}
    )

    datetime1 = DateTime.from_unix!(context.timestamp1)
    datetime2 = DateTime.from_unix!(context.timestamp2)

    # Inserts into the DB. Must delete it at the end of the test
    BurnRate.fetch_and_store(context.ticker, token_decimals)
    {:ok, burn_rates} = Store.burn_rate(context.ticker, datetime1, datetime2, "5m")

    assert {datetime1, context.expected_burn_rate1} in burn_rates
    assert {datetime2, context.expected_burn_rate2} in burn_rates

    Store.drop_measurement(context.ticker)
  end
end
