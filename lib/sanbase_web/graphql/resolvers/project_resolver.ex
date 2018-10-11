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

  def all_projects(parent, args, %{context: %{basic_auth: true}}), do: all_projects(parent, args)

  def all_projects(parent, args, %{context: %{current_user: user}}) when not is_nil(user), do: all_projects(parent, args)

  def all_projects(_parent, _args, _context), do: {:error, :unauthorized}

  defp all_projects(parent, args) do
    only_project_transparency = Map.get(args, :only_project_transparency, false)

    query = from p in Project,
    where: not ^only_project_transparency or p.project_transparency

    projects = case coinmarketcap_requested?(resolution) do
      true -> Repo.all(query) |> Repo.preload(:latest_coinmarketcap_data)
      _ -> Repo.all(query)
    end

    projects = case funds_raised_ico_price_requested?(resolution) do
      true -> Repo.preload(projects, [icos: [ico_currencies: [:currency]]])
      _ -> projects
    end

    {:ok, projects}
  end

  def project(parent, args, %{context: %{basic_auth: true}}), do: project(parent, args)

  def project(parent, args, %{context: %{current_user: user}}) when not is_nil(user), do: project(parent, args)

  def project(_parent, _args, _context), do: {:error, :unauthorized}

  defp project(parent, args) do
    id = Map.get(args, :id)

    project = case coinmarketcap_requested?(resolution) do
      true -> Repo.get(Project, id) |> Repo.preload(:latest_coinmarketcap_data)
      _ -> Repo.get(Project, id)
    end

    project = case funds_raised_ico_price_requested?(resolution) do
      true -> Repo.preload(project, [icos: [ico_currencies: [:currency]]])
      _ -> project
    end

    {:ok, project}
  end

  def all_projects_with_eth_contract_info(_parent, _args, resolution) do
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

    projects = case coinmarketcap_requested?(resolution) do
      true -> Repo.all(query) |> Repo.preload(:latest_coinmarketcap_data)
      _ -> Repo.all(query)
    end

    projects = case funds_raised_ico_price_requested?(resolution) do
      true -> Repo.preload(projects, [icos: [ico_currencies: [:currency]]])
      _ -> projects
    end

    {:ok, projects}
  end

  def eth_balance(%Project{id: id}, _args, resolution) do
    only_project_transparency = get_parent_args(resolution)
    |> Map.get(:only_project_transparency, false)

    query = from a in ProjectEthAddress,
    inner_join: wd in LatestEthWalletData, on: wd.address == a.address,
    where: a.project_id == ^id and
          (not ^only_project_transparency or a.project_transparency),
    select: sum(wd.balance)

    balance = Repo.one(query)

    {:ok, balance}
  end

  def btc_balance(%Project{id: id}, _args, resolution) do
    only_project_transparency = get_parent_args(resolution)
    |> Map.get(:only_project_transparency, false)

    query = from a in ProjectBtcAddress,
    inner_join: wd in LatestBtcWalletData, on: wd.address == a.address,
    where: a.project_id == ^id and
          (not ^only_project_transparency or a.project_transparency),
    select: sum(wd.satoshi_balance)

    balance = Repo.one(query)

    {:ok, balance}
  end

  def funds_raised_icos(%Project{} = project, _args, _resolution) do
    funds_raised = Project.funds_raised_icos(project, true)
    {:ok, funds_raised}
  end

  def market_segment(%Project{market_segment_id: nil}, _args, _resolution), do: {:ok, nil}
  def market_segment(%Project{market_segment_id: market_segment_id}, _args, _resolution) do
    %MarketSegment{name: market_segment} = Repo.get!(MarketSegment, market_segment_id)

    {:ok, market_segment}
  end

  def infrastructure(%Project{infrastructure_id: nil}, _args, _resolution), do: {:ok, nil}
  def infrastructure(%Project{infrastructure_id: infrastructure_id}, _args, _resolution) do
    %Infrastructure{code: infrastructure} = Repo.get!(Infrastructure, infrastructure_id)

    {:ok, infrastructure}
  end

  def project_transparency_status(%Project{project_transparency_status_id: nil}, _args, _resolution), do: {:ok, nil}
  def project_transparency_status(%Project{project_transparency_status_id: project_transparency_status_id}, _args, _resolution) do
    %ProjectTransparencyStatus{name: project_transparency_status} = Repo.get!(ProjectTransparencyStatus, project_transparency_status_id)

    {:ok, project_transparency_status}
  end

  def roi_usd(%Project{} = project, _args, _resolution) do
    roi = Project.roi_usd(project)

    {:ok, roi}
  end

  def symbol(%Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{symbol: symbol}}, _args, _resolution) do
    {:ok, symbol}
  end
  def symbol(_parent, _args, _resolution), do: {:ok, nil}

  def rank(%Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{rank: rank}}, _args, _resolution) do
    {:ok, rank}
  end
  def rank(_parent, _args, _resolution), do: {:ok, nil}

  def price_usd(%Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{price_usd: price_usd}}, _args, _resolution) do
    {:ok, price_usd}
  end
  def price_usd(_parent, _args, _resolution), do: {:ok, nil}

  def volume_usd(%Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{volume_usd: volume_usd}}, _args, _resolution) do
    {:ok, volume_usd}
  end
  def volume_usd(_parent, _args, _resolution), do: {:ok, nil}

  def marketcap_usd(%Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{market_cap_usd: market_cap_usd}}, _args, _resolution) do
    {:ok, market_cap_usd}
  end
  def marketcap_usd(_parent, _args, _resolution), do: {:ok, nil}

  def available_supply(%Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{available_supply: available_supply}}, _args, _resolution) do
    {:ok, available_supply}
  end
  def available_supply(_parent, _args, _resolution), do: {:ok, nil}

  def total_supply(%Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{total_supply: total_supply}}, _args, _resolution) do
    {:ok, total_supply}
  end
  def total_supply(_parent, _args, _resolution), do: {:ok, nil}

  def percent_change_1h(%Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{percent_change_1h: percent_change_1h}}, _args, _resolution) do
    {:ok, percent_change_1h}
  end
  def percent_change_1h(_parent, _args, _resolution), do: {:ok, nil}

  def percent_change_24h(%Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{percent_change_24h: percent_change_24h}}, _args, _resolution) do
    {:ok, percent_change_24h}
  end
  def percent_change_24h(_parent, _args, _resolution), do: {:ok, nil}

  def percent_change_7d(%Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{percent_change_7d: percent_change_7d}}, _args, _resolution) do
    {:ok, percent_change_7d}
  end
  def percent_change_7d(_parent, _args, _resolution), do: {:ok, nil}

  def funds_raised_usd_ico_price(%Project{} = project, _args, _resolution) do
    result = Project.funds_raised_usd_ico_price(project)

    {:ok, result}
  end

  def funds_raised_eth_ico_price(%Project{} = project, _args, _resolution) do
    result = Project.funds_raised_eth_ico_price(project)

    {:ok, result}
  end

  def funds_raised_btc_ico_price(%Project{} = project, _args, _resolution) do
    result = Project.funds_raised_btc_ico_price(project)

    {:ok, result}
  end

  def initial_ico(%Project{} = project, _args, resolution) do
    ico = Project.initial_ico(project)

    ico = case funds_raised_ico_price_requested?(resolution) do
      true -> Repo.preload(ico, [ico_currencies: [:currency]])
      _ -> ico
    end

    {:ok, ico}
  end

  def icos(%Project{} = project, _args, resolution) do
    project = case funds_raised_ico_price_requested?(resolution) do
      true -> Repo.preload(project, [icos: [ico_currencies: [:currency]]])
      _ -> Repo.preload(project, :icos)
    end

    {:ok, project.icos}
  end

  defp coinmarketcap_requested?(resolution) do
    case requested_fields(resolution) do
      %{symbol: true} -> true
      %{rank: true} -> true
      %{priceUsd: true} -> true
      %{volumeUsd: true} -> true
      %{marketcapUsd: true} -> true
      %{availableSupply: true} -> true
      %{totalSupply: true} -> true
      %{percent_change_1h: true} -> true
      %{percent_change_24h: true} -> true
      %{percent_change_7d: true} -> true
      _ -> false
    end
  end

  defp funds_raised_ico_price_requested?(resolution) do
    case requested_fields(resolution) do
      %{fundsRaisedUsdIcoPrice: true} -> true
      %{fundsRaisedEthIcoPrice: true} -> true
      %{fundsRaisedBtcIcoPrice: true} -> true
      _ -> false
    end
  end

  defp requested_fields(resolution) do
    resolution.definition.selections
    |> Enum.map(&(Map.get(&1, :name) |> String.to_atom()))
    |> Enum.into(%{}, fn field -> {field, true} end)
  end

  defp get_parent_args(resolution) do
    case resolution do
      %{path: [_, _, %{argument_data: parent_args} | _]} -> parent_args
      _ -> %{}
    end
  end
end
