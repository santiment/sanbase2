defmodule SanbaseWeb.Graphql.ProjectResolver do
  require Logger

  import Ecto.Query, warn: false

  alias Sanbase.Model.Project
  alias Sanbase.Model.ProjectEthAddress
  alias Sanbase.Model.ProjectBtcAddress
  alias Sanbase.Model.LatestBtcWalletData
  alias Sanbase.Model.LatestEthWalletData
  alias Sanbase.Model.Ico
  alias Sanbase.Model.IcoCurrencies
  alias Sanbase.Model.Currency

  alias Sanbase.Repo
  alias Ecto.Multi

  def all_projects(parent, args, context) do
    only_project_transparency = Map.get(args, :only_project_transparency, false)

    query = from p in Project,
    where: not ^only_project_transparency or p.project_transparency,
    select: p

    projects = Repo.all(query)

    {:ok, projects}
  end

  def eth_balance(%Project{id: id}, args, context) do
    only_project_transparency = get_parent_args(context)
    |> Map.get(:only_project_transparency, false)

    query = from a in ProjectEthAddress,
    inner_join: wd in LatestEthWalletData, on: wd.address == a.address,
    where: a.project_id == ^id and
          (not ^only_project_transparency or a.project_transparency),
    select: sum(wd.balance)

    balance = Repo.one(query)

    {:ok, balance}
  end

  def btc_balance(%Project{id: id}, args, context) do
    only_project_transparency = get_parent_args(context)
    |> Map.get(:only_project_transparency, false)

    query = from a in ProjectBtcAddress,
    inner_join: wd in LatestBtcWalletData, on: wd.address == a.address,
    where: a.project_id == ^id and
          (not ^only_project_transparency or a.project_transparency),
    select: sum(wd.satoshi_balance)

    balance = Repo.one(query)

    {:ok, balance}
  end

  def funds_raised_icos(%Project{id: id}, _args, _context) do
    query = from i in Ico,
    inner_join: ic in IcoCurrencies, on: ic.ico_id == i.id and not is_nil(ic.value),
    inner_join: c in Currency, on: c.id == ic.currency_id,
    where: i.project_id == ^id,
    group_by: [c.id, c.code],
    select: %{currency_code: c.code, amount: sum(ic.value)}

    funds_raised = Repo.all(query)
    |> case do
      [] ->
        fallback_query = from i in Ico,
        where: i.project_id == ^id,
        select: %{funds_raised_usd: sum(i.funds_raised_usd),
                  funds_raised_btc: sum(i.funds_raised_btc),
                  funds_raised_eth: sum(i.funds_raised_eth)}

        Repo.one(fallback_query)
        |> case do
          %{funds_raised_usd: funds_raised_usd} when not is_nil(funds_raised_usd) ->
            [%{currency_code: "USD", amount: funds_raised_usd}]
          %{funds_raised_btc: funds_raised_btc} when not is_nil(funds_raised_btc) ->
            [%{currency_code: "BTC", amount: funds_raised_btc}]
          %{funds_raised_eth: funds_raised_eth} when not is_nil(funds_raised_eth) ->
            [%{currency_code: "ETH", amount: funds_raised_eth}]
          _ -> []
        end
      funds -> funds
    end

    {:ok, funds_raised}
  end

  defp get_parent_args(context) do
    case context do
      %{path: [_, _, %{argument_data: parent_args} | _]} -> parent_args
      _ -> %{}
    end
  end
end
