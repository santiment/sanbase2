defmodule SanbaseWeb.Graphql.Resolvers.ProjectResolver do
  require Logger

  import Ecto.Query, warn: false
  import Absinthe.Resolution.Helpers

  alias Sanbase.Model.Project
  alias Sanbase.Model.LatestCoinmarketcapData
  alias Sanbase.Model.MarketSegment
  alias Sanbase.Model.Infrastructure
  alias Sanbase.Model.ProjectTransparencyStatus
  alias Sanbase.Model.ProjectEthAddress
  alias Sanbase.Prices
  alias Sanbase.Github
  alias Sanbase.ExternalServices.Etherscan

  alias SanbaseWeb.Graphql.SanbaseRepo
  alias SanbaseWeb.Graphql.PriceStore

  alias Sanbase.Repo

  def all_projects(_parent, args, _resolution, only_project_transparency \\ nil) do
    only_project_transparency =
      case only_project_transparency do
        nil -> Map.get(args, :only_project_transparency, false)
        value -> value
      end

    query =
      cond do
        only_project_transparency ->
          from(p in Project, where: p.project_transparency, order_by: p.name)

        true ->
          from(p in Project, where: not is_nil(p.coinmarketcap_id), order_by: p.name)
      end

    projects =
      query
      |> Repo.all()
      |> Repo.preload([
        :latest_coinmarketcap_data,
        icos: [ico_currencies: [:currency]]
      ])

    {:ok, projects}
  end

  def project(_parent, args, _resolution) do
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

  def eth_spent(%Project{ticker: ticker}, %{days: days}, _resolution) do
    async(fn ->
      today = Timex.now()
      days_ago = Timex.shift(today, days: -days)

      eth_spent =
        Etherscan.Store.trx_sum_in_interval!(
          ticker,
          days_ago,
          today,
          "out"
        )

      {:ok, eth_spent}
    end)
  end

  def eth_transactions(
        %Project{ticker: ticker},
        %{from: from, to: to, transaction_type: trx_type},
        _resolution
      ) do
    async(fn ->
      with trx_type <- trx_type |> Atom.to_string(),
           {:ok, eth_transactions} <- Etherscan.Store.transactions(ticker, from, to, trx_type) do
        result =
          eth_transactions
          |> Enum.map(fn {datetime, trx_volume, trx_type, from_addr, to_addr} ->
            %{
              datetime: datetime,
              transaction_volume: trx_volume |> Decimal.new(),
              transaction_type: trx_type,
              from_address: from_addr,
              to_address: to_addr
            }
          end)

        {:ok, result}
      else
        _error ->
          {:error, nil}
      end
    end)
  end

  def eth_balance(%Project{} = project, _args, %{context: %{loader: loader}}) do
    loader
    |> eth_balance_loader(project)
    |> on_load(&eth_balance_from_loader(&1, project))
  end

  defp eth_balance_loader(loader, project) do
    loader
    |> Dataloader.load(SanbaseRepo, :eth_addresses, project)
  end

  defp eth_balance_from_loader(loader, project) do
    balance =
      loader
      |> Dataloader.get(SanbaseRepo, :eth_addresses, project)
      |> Stream.map(& &1.latest_eth_wallet_data)
      |> Stream.reject(&is_nil/1)
      |> Stream.map(& &1.balance)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

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
      |> Stream.map(& &1.latest_btc_wallet_data)
      |> Stream.reject(&is_nil/1)
      |> Stream.map(& &1.balance)
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
    async(fn ->
      pair = "#{ticker}_USD"
      yesterday = Timex.shift(Timex.now(), days: -1)
      the_other_day = Timex.shift(Timex.now(), days: -2)

      with [[_dt, today_vol]] <- Prices.Store.fetch_mean_volume(pair, yesterday, Timex.now()),
           [[_dt, yesterday_vol]] <-
             Prices.Store.fetch_mean_volume(pair, the_other_day, yesterday),
           true <- yesterday_vol > 0 do
        {:ok, (today_vol - yesterday_vol) * 100 / yesterday_vol}
      else
        _ ->
          {:ok, nil}
      end
    end)
  end

  def average_dev_activity(%Project{ticker: ticker}, _args, _resolution) do
    async(fn ->
      month_ago = Timex.shift(Timex.now(), days: -30)

      case Github.Store.fetch_total_activity(ticker, month_ago, Timex.now()) do
        {:ok, {_dt, total_activity}} ->
          {:ok, total_activity / 30}

        _ ->
          {:ok, 0}
      end
    end)
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
    {:ok, percent_change_1h}
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
    {:ok, percent_change_24h}
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
    {:ok, percent_change_7d}
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

  def price_to_book_ratio(%Project{} = project, _args, %{context: %{loader: loader}}) do
    loader
    |> usd_balance_loader(project)
    |> on_load(fn loader ->
      with {:ok, usd_balance} <- usd_balance_from_loader(loader, project),
           {:ok, market_cap} <- marketcap_usd(project, nil, nil),
           false <- is_nil(usd_balance) || is_nil(market_cap),
           false <- Decimal.cmp(usd_balance, Decimal.new(0)) == :eq do
        {:ok, Decimal.div(market_cap, usd_balance)}
      else
        _ ->
          {:ok, nil}
      end
    end)
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

  def eth_address_balance(%ProjectEthAddress{} = eth_address, _args, %{
        context: %{loader: loader}
      }) do
    loader
    |> Dataloader.load(SanbaseRepo, :latest_eth_wallet_data, eth_address)
    |> on_load(fn loader ->
      latest_eth_wallet_data =
        Dataloader.get(loader, SanbaseRepo, :latest_eth_wallet_data, eth_address)

      {:ok, latest_eth_wallet_data.balance}
    end)
  end
end
