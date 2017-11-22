defmodule :"Elixir.Sanbase.Repo.Migrations.Add-top-20-cmc-projects-to-db" do
  use Ecto.Migration

  alias Sanbase.Model.Project
  alias Sanbase.Repo

  def up do
    [
      %Project{name: "Bitcoin", ticker: "BTC", coinmarketcap_id: "bitcoin"},
      %Project{name: "Ethereum", ticker: "ETH", coinmarketcap_id: "ethereum"},
      %Project{name: "Bitcoin Cash", ticker: "BCH", coinmarketcap_id: "bitcoin-cash"},
      %Project{name: "Ripple", ticker: "XRP", coinmarketcap_id: "ripple"},
      %Project{name: "Dash", ticker: "DASH", coinmarketcap_id: "dash"},
      %Project{name: "Litecoin", ticker: "LTC", coinmarketcap_id: "litecoin"},
      %Project{name: "IOTA", ticker: "MIOTA", coinmarketcap_id: "iota"},
      %Project{name: "NEO", ticker: "NEO", coinmarketcap_id: "neo"},
      %Project{name: "Monero", ticker: "XMR", coinmarketcap_id: "monero"},
      %Project{name: "NEM", ticker: "XEM", coinmarketcap_id: "nem"},
      %Project{name: "Ethereum Classic", ticker: "ETC", coinmarketcap_id: "ethereum-classic"},
      %Project{name: "Lisk", ticker: "LSK", coinmarketcap_id: "lisk"},
      %Project{name: "Qtum", ticker: "QTUM", coinmarketcap_id: "qtum"},
      %Project{name: "EOS", ticker: "EOS", coinmarketcap_id: "eos"},
      %Project{name: "OmiseGO", ticker: "OMG", coinmarketcap_id: "omisego"},
      %Project{name: "Zcash", ticker: "ZEC", coinmarketcap_id: "zcash"},
      %Project{name: "Cardano", ticker: "ADA", coinmarketcap_id: "cardano"},
      %Project{name: "Hshare", ticker: "HSR", coinmarketcap_id: "hshare"},
      %Project{name: "Stellar Lumens", ticker: "XLM", coinmarketcap_id: "stellar"},
      %Project{name: "Tether", ticker: "USDT", coinmarketcap_id: "tether"}
    ]
    |> Enum.each(fn project ->
      project
      |> find_existing_project()
      |> Repo.insert_or_update!
    end)
  end

  defp find_existing_project(%Project{name: name} = project) do
    case Repo.get_by(Project, name: name) do
      nil -> Project.changeset(project)
      existing_project -> Project.changeset(existing_project, Map.from_struct(project))
    end
  end
end
