defmodule Sanbase.ProjectByCurrencyDuplicateTickerTest do
  # Reproduces SANBASE-BACKEND-PROD-FBV: Project.by_currency/1 uses Repo.one/1
  # on `ticker == ^code`, but tickers are not unique (prod has 2 projects with
  # ticker "ETH"), so fundsRaised*IcoEndPrice raises Ecto.MultipleResultsError.
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Project
  alias Sanbase.Model.Currency

  setup do
    ethereum = insert(:project, %{name: "Ethereum", slug: "ethereum", ticker: "ETH"})
    impostor = insert(:project, %{name: "Ether Impostor", slug: "ether-impostor", ticker: "ETH"})

    %{ethereum: ethereum, impostor: impostor}
  end

  test "by_currency/1 does not raise when several projects share the ticker" do
    assert %Project{ticker: "ETH"} = Project.by_currency(%Currency{code: "ETH"})
  end

  test "fundsRaisedBtcIcoEndPrice does not raise with duplicate tickers" do
    currency_eth = insert(:currency, %{code: "ETH"})
    project = insert(:random_project)
    ico = insert(:ico, %{project_id: project.id, end_date: ~D[2017-10-17]})
    insert(:ico_currency, %{ico_id: ico.id, currency_id: currency_eth.id, amount: 100})

    Sanbase.Mock.prepare_mock(Sanbase.Price, :last_record_before, fn _slug, _datetime ->
      {:ok, %{price_usd: 10, price_btc: 0.5, marketcap: 100, volume: 100}}
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      ico = Sanbase.Repo.get!(Sanbase.Model.Ico, ico.id)
      assert Sanbase.Model.Ico.funds_raised_btc_ico_end_price(ico) == 50.0
    end)
  end
end
