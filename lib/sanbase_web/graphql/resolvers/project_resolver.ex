defmodule SanbaseWeb.Graphql.Resolvers.ProjectResolver do
  require Logger

  import Ecto.Query, warn: false

  alias Sanbase.Model.Project
  alias Sanbase.Model.ProjectEthAddress
  alias Sanbase.Model.ProjectBtcAddress
  alias Sanbase.Model.LatestBtcWalletData
  alias Sanbase.Model.LatestEthWalletData
  alias Sanbase.Model.LatestCoinmarketcapData
  alias Sanbase.Model.Ico
  alias Sanbase.Model.Currency
  alias Sanbase.Model.MarketSegment
  alias Sanbase.Model.Infrastructure
  alias Sanbase.Model.ProjectTransparencyStatus

  alias Sanbase.Repo

  def all_projects(_parent, args, context) do
    only_project_transparency = Map.get(args, :only_project_transparency, false)

    query = from p in Project,
    where: not ^only_project_transparency or p.project_transparency

    projects = case coinmarketcap_requested?(context) do
      true -> Repo.all(query) |> Repo.preload(:latest_coinmarketcap_data)
      _ -> Repo.all(query)
    end

    {:ok, projects}
  end

  def project(_parent, args, context) do
    id = Map.get(args, :id)

    project = case coinmarketcap_requested?(context) do
      true -> Repo.get(Project, id) |> Repo.preload(:latest_coinmarketcap_data)
      _ -> Repo.get(Project, id)
    end

    {:ok, project}
  end

  def all_projects_with_eth_contract_info(_parent, _args, context) do
    all_icos_query = from i in Ico,
    select: %{project_id: i.project_id,
              main_contract_address: i.main_contract_address,
              contract_block_number: i.contract_block_number,
              contract_abi: i.contract_abi,
              rank: fragment("row_number() over(partition by ? order by ? asc)", i.project_id, i.start_date)}

    query = from d in subquery(all_icos_query),
    inner_join: p in Project, on: p.id == d.project_id,
    where: d.rank == 1
          and not is_nil(d.main_contract_address)
          and not is_nil(d.contract_block_number)
          and not is_nil(d.contract_abi),
    select: p

    projects = case coinmarketcap_requested?(context) do
      true -> Repo.all(query) |> Repo.preload(:latest_coinmarketcap_data)
      _ -> Repo.all(query)
    end

    {:ok, projects}
  end

  def eth_balance(%Project{id: id}, _args, context) do
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

  def btc_balance(%Project{id: id}, _args, context) do
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

  def market_segment(%Project{market_segment_id: nil}, _args, _context), do: {:ok, nil}
  def market_segment(%Project{market_segment_id: market_segment_id}, _args, _context) do
    %MarketSegment{name: market_segment} = Repo.get!(MarketSegment, market_segment_id)

    {:ok, market_segment}
  end

  def infrastructure(%Project{infrastructure_id: nil}, _args, _context), do: {:ok, nil}
  def infrastructure(%Project{infrastructure_id: infrastructure_id}, _args, _context) do
    %Infrastructure{code: infrastructure} = Repo.get!(Infrastructure, infrastructure_id)

    {:ok, infrastructure}
  end

  def project_transparency_status(%Project{project_transparency_status_id: nil}, _args, _context), do: {:ok, nil}
  def project_transparency_status(%Project{project_transparency_status_id: project_transparency_status_id}, _args, _context) do
    %ProjectTransparencyStatus{name: project_transparency_status} = Repo.get!(ProjectTransparencyStatus, project_transparency_status_id)

    {:ok, project_transparency_status}
  end

  def roi_usd(%Project{} = project, _args, _context) do
    roi = Project.roi_usd(project)

    {:ok, roi}
  end

  def rank(%Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{rank: rank}}, _args, _context) do
    {:ok, rank}
  end
  def rank(_parent, _args, _context), do: {:ok, nil}

  def price_usd(%Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{price_usd: price_usd}}, _args, _context) do
    {:ok, price_usd}
  end
  def price_usd(_parent, _args, _context), do: {:ok, nil}

  def volume_usd(%Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{volume_usd: volume_usd}}, _args, _context) do
    {:ok, volume_usd}
  end
  def volume_usd(_parent, _args, _context), do: {:ok, nil}

  def market_cap_usd(%Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{market_cap_usd: market_cap_usd}}, _args, _context) do
    {:ok, market_cap_usd}
  end
  def market_cap_usd(_parent, _args, _context), do: {:ok, nil}

  def available_supply(%Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{available_supply: available_supply}}, _args, _context) do
    {:ok, available_supply}
  end
  def available_supply(_parent, _args, _context), do: {:ok, nil}

  def total_supply(%Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{total_supply: total_supply}}, _args, _context) do
    {:ok, total_supply}
  end
  def total_supply(_parent, _args, _context), do: {:ok, nil}

  def initial_ico(%Project{} = project, _args, _context) do
    ico = Project.initial_ico(project)

    {:ok, ico}
  end

  def ico_cap_currency(%Ico{cap_currency_id: nil}, _args, _context), do: {:ok, nil}
  def ico_cap_currency(%Ico{cap_currency_id: cap_currency_id}, _args, _context) do
    %Currency{code: currency_code} = Repo.get!(Currency, cap_currency_id)

    {:ok, currency_code}
  end

  def ico_currency_amounts(%Ico{id: id}, _args, _context) do
    query = from i in Ico,
    left_join: ic in assoc(i, :ico_currencies),
    inner_join: c in assoc(ic, :currency),
    where: i.id == ^id,
    select: %{currency_code: c.code, amount: ic.amount}

    currency_amounts = Repo.all(query)

    {:ok, currency_amounts}
  end

  defp coinmarketcap_requested?(context) do
    case requested_fields(context) do
      %{rank: true} -> true
      %{priceUsd: true} -> true
      %{volumeUsd: true} -> true
      %{marketCapUsd: true} -> true
      %{availableSupply: true} -> true
      %{totalSupply: true} -> true
      _ -> false
    end
  end

  defp requested_fields(context) do
    context.definition.selections
    |> Enum.map(&(Map.get(&1, :name) |> String.to_atom()))
    |> Enum.into(%{}, fn field -> {field, true} end)
  end

  defp get_parent_args(context) do
    case context do
      %{path: [_, _, %{argument_data: parent_args} | _]} -> parent_args
      _ -> %{}
    end
  end
end
