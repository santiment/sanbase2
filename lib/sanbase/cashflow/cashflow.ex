defmodule Sanbase.Cashflow do

  import Ecto.Query, warn: false
  alias Sanbase.Repo

  alias Sanbase.Model.{Project, LatestCoinmarketcapData, ProjectEthAddress, TrackedEth, LatestEthWalletData}

  def get_project_data do
    query = from p in Project,
            inner_join: a in ProjectEthAddress, on: a.project_id == p.id,
            inner_join: ta in TrackedEth, on: ta.address == a.address,
            left_join: wd in LatestEthWalletData, on: wd.address == a.address,
            left_join: mc in LatestCoinmarketcapData, on: mc.id == p.coinmarketcap_id,
            select: %{project: p, coinmarketcap: mc, wallet_data: wd}

    # TODO: return it in a better structure - aggregated by project
    Repo.all(query)
  end
end
