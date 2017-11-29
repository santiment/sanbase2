defmodule Sanbase.Cashflow do

  import Ecto.Query, warn: false
  alias Sanbase.Repo

  alias Sanbase.Model.{Project, LatestCoinmarketcapData, ProjectEthAddress, LatestEthWalletData}

  def get_project_data do
    query = from p in Project,
            inner_join: a in ProjectEthAddress, on: a.project_id == p.id,
            inner_join: mc in LatestCoinmarketcapData, on: mc.coinmarketcap_id == p.coinmarketcap_id,
            left_join: wd in LatestEthWalletData, on: wd.address == a.address,
            select: %{project: p, coinmarketcap: mc, wallet_data: wd}

    # TODO: return it in a better structure - aggregated by project
    Repo.all(query)
  end
end
