defmodule Sanbase.Etherbi.UtilsTest do
  use SanbaseWeb.ConnCase
  use Phoenix.ConnTest

  alias Sanbase.Model.Project
  alias Sanbase.Model.Ico

  setup do
    ticker1 = "SAN"
    ticker2 = "TEST"
    ticker1_decimal_places = 18

    p =
      %Project{}
      |> Project.changeset(%{
        name: "Santiment",
        ticker: ticker1,
        token_decimals: ticker1_decimal_places,
        coinmarketcap_id: "santiment"
      })
      |> Sanbase.Repo.insert!()

    %Project{}
    |> Project.changeset(%{name: "SomethingElse", ticker: ticker2})
    |> Sanbase.Repo.insert!()

    %Ico{}
    |> Ico.changeset(%{
      project_id: p.id,
      main_contract_address: "0x1232",
      contract_block_number: 55,
      contract_abi: "0x321",
      rank: 1
    })
    |> Sanbase.Repo.insert!()

    [
      ticker1: ticker1,
      ticker1_decimal_places: ticker1_decimal_places,
      ticker2: ticker2
    ]
  end

  test "tickers with no decimal places are not fetched", context do
    tickers = Sanbase.Etherbi.Utils.get_tickers()

    assert [context.ticker1] == tickers
  end

  test "build token decimals map", context do
    token_decimals = Sanbase.Etherbi.Utils.build_token_decimals_map()

    assert token_decimals == %{context.ticker1 => :math.pow(10, context.ticker1_decimal_places)}
  end
end