defmodule SanbaseWeb.Graphql.Resolvers.ProjectResolver do
  require Logger

  import Ecto.Query, warn: false
  import Absinthe.Resolution.Helpers

  alias Sanbase.Model.Project
  alias Sanbase.Model.LatestCoinmarketcapData
  alias Sanbase.Model.MarketSegment
  alias Sanbase.Model.Infrastructure
  alias Sanbase.Model.ProjectTransparencyStatus
  alias Sanbase.Prices
  alias Sanbase.Github

  alias SanbaseWeb.Graphql.SanbaseRepo
  alias SanbaseWeb.Graphql.PriceStore

  alias Sanbase.Repo

  def all_projects(parent, args, %{context: %{basic_auth: true}}), do: all_projects(parent, args)

  def all_projects(parent, args, %{context: %{current_user: user}}) when not is_nil(user), do: all_projects(parent, args)

  def all_projects(_parent, _args, _context), do: {:error, :unauthorized}

  defp all_projects(parent, args) do
    only_project_transparency = Map.get(args, :only_project_transparency, false)

    query = cond do
      only_project_transparency ->
        from p in Project,
        where: p.project_transparency
      true ->
        from p in Project,
        where: not is_nil(p.coinmarketcap_id)
    end

    projects = case coinmarketcap_requested?(resolution) do
      true -> Repo.all(query) |> Repo.preload([:latest_coinmarketcap_data, icos: [ico_currencies: [:currency]]])
      _ -> Repo.all(query)
    end

    {:ok, projects}
  end

  def project(parent, args, %{context: %{basic_auth: true}}), do: project(parent, args)

  def project(parent, args, %{context: %{current_user: user}}) when not is_nil(user), do: project(parent, args)

  def project(_parent, _args, _context), do: {:error, :unauthorized}

  defp project(parent, args) do
    id = Map.get(args, :id)

    project =
      Project
      |> Repo.get(id)
      |> Repo.preload([:latest_coinmarketcap_data, icos: [ico_currencies: [:currency]]])

    {:ok, project}
  end

  def all_projects_with_eth_contract_info(_parent, _args, _resolution) do
    query = Project.all_projects_with_eth_contract_query()

    projects =
      query
      |> Repo.all()
      |> Repo.preload([:latest_coinmarketcap_data, icos: [ico_currencies: [:currency]]])

    {:ok, projects}
  end

  def eth_balance(%Project{} = project, _args, %{context: %{loader: loader}}) do
    loader
    |> eth_balance_loader(project)
    |> on_load(&eth_balance_from_loader(&1, project))
  end

  def eth_spent(%Project{id: id}, %{from: from, to: to}, _resolution) do
    coinmarketcap_id =
      Repo.one(from(p in Project, where: p.id == ^id, select: p.coinmarketcap_id))

    [{_datetime, eth_spent}] =
      Sanbase.ExternalServices.Etherscan.Store.trx_sum_in_interval!(
        coinmarketcap_id,
        from,
        to,
        "out"
      )

    {:ok, eth_spent |> Decimal.new()}
  end

  def eth_balances_by_id(only_project_transparency, project_ids) do
    query =
      from(
        a in ProjectEthAddress,
        inner_join: wd in LatestEthWalletData,
        on: wd.address == a.address,
        where:
          a.project_id in ^project_ids and
            (not (^only_project_transparency) or a.project_transparency),
        group_by: a.project_id,
        select: %{project_id: a.project_id, balance: sum(wd.balance)}
      )

    balances = Repo.all(query)

    {:ok, balance}
  end

  def btc_balance(%Project{} = project, _args, %{context: %{loader: loader}}) do
    loader
    |> btc_balance_loader(project)
    |> on_load(&btc_balance_from_loader(&1, project))
  end

  defp btc_balance_loader(loader, project) do
    loader
    |> Dataloader.load(SanbaseRepo, :btc_addresses, project)
  end

  def btc_balance_from_loader(loader, project) do
    balance =
      loader
      |> Dataloader.get(SanbaseRepo, :btc_addresses, project)
      |> Enum.map(& &1.latest_btc_wallet_data)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.balance)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    {:ok, balance}
  end

  def usd_balance(%Project{} = project, _args, %{context: %{loader: loader}}) do
    loader
    |> usd_balance_loader(project)
    |> on_load(&usd_balance_from_loader(&1, project))
  end

  defp usd_balance_loader(loader, project) do
    loader
    |> eth_balance_loader(project)
    |> btc_balance_loader(project)
    |> Dataloader.load(PriceStore, "ETH_USD", :last)
    |> Dataloader.load(PriceStore, "BTC_USD", :last)
  end

  defp usd_balance_from_loader(loader, project) do
    {:ok, eth_balance} = eth_balance_from_loader(loader, project)
    {:ok, btc_balance} = btc_balance_from_loader(loader, project)
    eth_price = Dataloader.get(loader, PriceStore, "ETH_USD", :last)
    btc_price = Dataloader.get(loader, PriceStore, "BTC_USD", :last)

    {:ok,
     Decimal.add(
       Decimal.mult(eth_balance, eth_price),
       Decimal.mult(btc_balance, btc_price)
     )}
  end

  def funds_raised_icos(%Project{} = project, _args, _resolution) do
    funds_raised = Project.funds_raised_icos(project)
    {:ok, funds_raised}
  end

  def market_segment(%Project{market_segment_id: nil}, _args, _resolution), do: {:ok, nil}

  def market_segment(%Project{market_segment_id: market_segment_id}, _args, _resolution) do
    batch({__MODULE__, :market_segments_by_id}, market_segment_id, fn batch_results ->
      {:ok, Map.get(batch_results, market_segment_id)}
    end)
  end

  def market_segments_by_id(_, market_segment_ids) do
    market_segments =
      from(i in MarketSegment, where: i.id in ^market_segment_ids)
      |> Repo.all()

    Map.new(market_segments, fn market_segment -> {market_segment.id, market_segment.name} end)
  end

  def infrastructure(%Project{infrastructure_id: nil}, _args, _resolution), do: {:ok, nil}

  def infrastructure(%Project{infrastructure_id: infrastructure_id}, _args, _resolution) do
    batch({__MODULE__, :infrastructures_by_id}, infrastructure_id, fn batch_results ->
      {:ok, Map.get(batch_results, infrastructure_id)}
    end)
  end

  def infrastructures_by_id(_, infrastructure_ids) do
    infrastructures =
      from(i in Infrastructure, where: i.id in ^infrastructure_ids)
      |> Repo.all()

    Map.new(infrastructures, fn infrastructure -> {infrastructure.id, infrastructure.code} end)
  end

  def project_transparency_status(
        %Project{project_transparency_status_id: nil},
        _args,
        _resolution
      ),
      do: {:ok, nil}

  def project_transparency_status(
        %Project{project_transparency_status_id: project_transparency_status_id},
        _args,
        _resolution
      ) do
    batch(
      {__MODULE__, :project_transparency_statuses_by_id},
      project_transparency_status_id,
      fn batch_results ->
        {:ok, Map.get(batch_results, project_transparency_status_id)}
      end
    )
  end

  def project_transparency_statuses_by_id(_, project_transparency_status_ids) do
    project_transparency_statuses =
      from(i in ProjectTransparencyStatus, where: i.id in ^project_transparency_status_ids)
      |> Repo.all()

    Map.new(project_transparency_statuses, fn project_transparency_status ->
      {project_transparency_status.id, project_transparency_status.name}
    end)
  end

  def roi_usd(%Project{} = project, _args, _resolution) do
    roi = Project.roi_usd(project)

    {:ok, roi}
  end

  def symbol(
        %Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{symbol: symbol}},
        _args,
        _resolution
      ) do
    {:ok, symbol}
  end

  def symbol(_parent, _args, _resolution), do: {:ok, nil}

  def rank(
        %Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{rank: rank}},
        _args,
        _resolution
      ) do
    {:ok, rank}
  end

  def rank(_parent, _args, _resolution), do: {:ok, nil}

  def price_usd(
        %Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{price_usd: price_usd}},
        _args,
        _resolution
      ) do
    {:ok, price_usd}
  end

  def price_usd(_parent, _args, _resolution), do: {:ok, nil}

  def volume_usd(
        %Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{volume_usd: volume_usd}},
        _args,
        _resolution
      ) do
    {:ok, volume_usd}
  end

  def volume_usd(_parent, _args, _resolution), do: {:ok, nil}

  def volume_change_24h(%Project{ticker: ticker}, _args, _resolution) do
    two_days_ago = Timex.shift(Timex.now(), days: -1)

    case Prices.Store.fetch_prices_with_resolution(
           "#{ticker}_USD",
           two_days_ago,
           Timex.now(),
           "1d"
         ) do
      [[_dt1, _price1, volume1, _mcap1], [_dt2, _price2, volume2, _mcap2]] ->
        {:ok, (volume2 - volume1) * 100 / volume1}

      [] ->
        {:ok, nil}
    end
  end

  def average_dev_activity(%Project{ticker: ticker}, _args, _resolution) do
    month_ago = Timex.shift(Timex.now(), days: -30)

    case Github.Store.fetch_activity_with_resolution!(ticker, month_ago, Timex.now(), "30d") do
      {_dt, total_activity} ->
        {:ok, total_activity / 30}

      _ ->
        {:ok, nil}
    end
  end

  def marketcap_usd(
        %Project{
          latest_coinmarketcap_data: %LatestCoinmarketcapData{market_cap_usd: market_cap_usd}
        },
        _args,
        _resolution
      ) do
    {:ok, market_cap_usd}
  end

  def marketcap_usd(_parent, _args, _resolution), do: {:ok, nil}

  def available_supply(
        %Project{
          latest_coinmarketcap_data: %LatestCoinmarketcapData{available_supply: available_supply}
        },
        _args,
        _resolution
      ) do
    {:ok, available_supply}
  end

  def available_supply(_parent, _args, _resolution), do: {:ok, nil}

  def total_supply(
        %Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{total_supply: total_supply}},
        _args,
        _resolution
      ) do
    {:ok, total_supply}
  end

  def total_supply(_parent, _args, _resolution), do: {:ok, nil}

  def percent_change_1h(
        %Project{
          latest_coinmarketcap_data: %LatestCoinmarketcapData{
            percent_change_1h: percent_change_1h
          }
        },
        _args,
        _resolution
      ) do
    {:ok, percent_change_1h |> Decimal.to_float()}
  end

  def percent_change_1h(_parent, _args, _resolution), do: {:ok, nil}

  def percent_change_24h(
        %Project{
          latest_coinmarketcap_data: %LatestCoinmarketcapData{
            percent_change_24h: percent_change_24h
          }
        },
        _args,
        _resolution
      ) do
    {:ok, percent_change_24h |> Decimal.to_float()}
  end

  def percent_change_24h(_parent, _args, _resolution), do: {:ok, nil}

  def percent_change_7d(
        %Project{
          latest_coinmarketcap_data: %LatestCoinmarketcapData{
            percent_change_7d: percent_change_7d
          }
        },
        _args,
        _resolution
      ) do
    {:ok, percent_change_7d |> Decimal.to_float()}
  end

  def percent_change_7d(_parent, _args, _resolution), do: {:ok, nil}

  def funds_raised_usd_ico_end_price(%Project{} = project, _args, _resolution) do
    result = Project.funds_raised_usd_ico_end_price(project)

    {:ok, result}
  end

  def funds_raised_eth_ico_end_price(%Project{} = project, _args, _resolution) do
    result = Project.funds_raised_eth_ico_end_price(project)

    {:ok, result}
  end

  def funds_raised_btc_ico_end_price(%Project{} = project, _args, _resolution) do
    result = Project.funds_raised_btc_ico_end_price(project)

    {:ok, result}
  end

  def initial_ico(%Project{} = project, _args, _resolution) do
    ico =
      Project.initial_ico(project)
      |> Repo.preload(ico_currencies: [:currency])

    {:ok, ico}
  end

  def signals(%Project{} = project, _args, %{context: %{loader: loader}}) do
    loader
    |> usd_balance_loader(project)
    |> on_load(fn loader ->
      with {:ok, usd_balance} <- usd_balance_from_loader(loader, project),
           {:ok, market_cap} <- marketcap_usd(project, nil, nil),
           false <- is_nil(usd_balance) || is_nil(market_cap),
           :lt <- Decimal.cmp(market_cap, usd_balance) do
        {:ok,
         [
           %{
             name: "balance_bigger_than_mcap",
             description: "The balance of the project is bigger than it's market capitalization"
           }
         ]}
      else
        _ ->
          {:ok, []}
      end
    end)
  end
end
