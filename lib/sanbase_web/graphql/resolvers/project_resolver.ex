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

  def all_projects(parent, args, %{context: %{auth: %{auth_method: :basic}}}), do: all_projects(parent, args)

  def all_projects(parent, args, %{context: %{auth: %{auth_method: :user_token}}}), do: all_projects(parent, args)

  def all_projects(_parent, _args, _context), do: {:error, :unauthorized}

  defp all_projects(parent, args) do
    only_project_transparency = Map.get(args, :only_project_transparency, false)

    query = from p in Project,
    where: not ^only_project_transparency or p.project_transparency

    projects = Repo.all(query)

    {:ok, projects}
  end

  def project(parent, args, %{context: %{auth: %{auth_method: :basic}}}), do: project(parent, args)

  def project(parent, args, %{context: %{auth: %{auth_method: :user_token}}}), do: project(parent, args)

  def project(_parent, _args, _context), do: {:error, :unauthorized}

  defp project(parent, args) do
    id = Map.get(args, :id)

    project = Repo.get(Project, id)

    {:ok, project}
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

  # If there is no raw data for any currency for a given ico, then fallback one of the precalculated totals - one of Ico.funds_raised_usd, Ico.funds_raised_btc, Ico.funds_raised_eth (checked in that order)
  def funds_raised_icos(%Project{id: id}, _args, _context) do
    # We have to aggregate all amounts for every currency for every ICO of the given project, this is the last part of the query (after the with clause).
    # The data to be aggreagated has to be fetched and unioned from two different sources (the "union all" inside the with clause):
    #   * For ICOs that have raw data entered for at least one currency we aggregate it by currency (the first query)
    #   * For ICOs that don't have that data entered (currently everything imported from the spreadsheet) we fall back to a precalculated total (the second query)
    query =
      '''
      with data as (select c.code currency_code, ic.amount
      from icos i
      join ico_currencies ic
      	on ic.ico_id = i.id
      		and ic.amount is not null
      join currencies c
      	on c.id = ic.currency_id
      where i.project_id = $1
      union all
      select case
      		when i.funds_raised_usd is not null then 'USD'
      		when i.funds_raised_btc is not null then 'BTC'
      		when i.funds_raised_eth is not null then 'ETH'
      		else null
      	end currency_code
      	, coalesce(i.funds_raised_usd, i.funds_raised_btc, i.funds_raised_eth) amount
      from icos i
      where i.project_id = $1
      	and not exists (select 1
      		from ico_currencies ic
      		where ic.ico_id = i.id
      			and ic.amount is not null))
      select d.currency_code, sum(d.amount) amount
      from data d
      where d.currency_code is not null
      group by d.currency_code
      order by case
          			when d.currency_code = 'BTC' then '_'
          			when d.currency_code = 'ETH' then '__'
          			when d.currency_code = 'USD' then '___'
          			else d.currency_code
          		end
      '''

      %{rows: rows} = Ecto.Adapters.SQL.query!(Sanbase.Repo, query, [id])

      funds_raised = rows
      |> Enum.map(fn([currency_code, amount]) -> %{currency_code: currency_code, amount: amount} end)

      {:ok, funds_raised}
  end

  defp get_parent_args(context) do
    case context do
      %{path: [_, _, %{argument_data: parent_args} | _]} -> parent_args
      _ -> %{}
    end
  end
end
