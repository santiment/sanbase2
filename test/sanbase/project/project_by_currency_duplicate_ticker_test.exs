defmodule Sanbase.ProjectByCurrencyDuplicateTickerTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Project
  alias Sanbase.Model.Currency

  test "by_currency/1 returns the best ranked of the projects sharing the ticker" do
    # Inserted first, so it has the lower id
    insert(:project, %{name: "Ether Impostor", slug: "ether-impostor", ticker: "ETH"})

    insert(:project, %{
      name: "Ethereum",
      slug: "ethereum",
      ticker: "ETH",
      coinmarketcap_id: "ethereum"
    })

    insert(:latest_cmc_data, %{coinmarketcap_id: "ethereum", rank: 2})

    assert %Project{slug: "ethereum"} = Project.by_currency(%Currency{code: "ETH"})
  end
end
