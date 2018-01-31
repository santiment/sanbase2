defmodule SanbaseWeb.Graphql.Resolvers.ProjectResolver do
  require Logger

  import Ecto.Query, warn: false
  import Absinthe.Resolution.Helpers

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

  def all_projects(_parent, args, resolution, only_project_transparency \\ nil) do
    only_project_transparency =
      case only_project_transparency do
        nil -> Map.get(args, :only_project_transparency, false)
        value -> value
      end

    query =
      cond do
        only_project_transparency ->
          from(p in Project, where: p.project_transparency)

        true ->
          from(p in Project, where: not is_nil(p.coinmarketcap_id))
      end

    projects =
      case coinmarketcap_requested?(resolution) do
        true ->
          Repo.all(query)
          |> Repo.preload([:latest_coinmarketcap_data, icos: [ico_currencies: [:currency]]])

        _ ->
          Repo.all(query)
      end

    {:ok, projects}
  end

  def project(_parent, args, resolution) do
    id = Map.get(args, :id)

    project =
      case coinmarketcap_requested?(resolution) do
        true ->
          Repo.get(Project, id)
          |> Repo.preload([:latest_coinmarketcap_data, icos: [ico_currencies: [:currency]]])

        _ ->
          Repo.get(Project, id)
      end

    {:ok, project}
  end

  def all_projects_with_eth_contract_info(_parent, _args, resolution) do
    query = Project.all_projects_with_eth_contract_query()

    projects =
      case coinmarketcap_requested?(resolution) do
        true ->
          Repo.all(query)
          |> Repo.preload([:latest_coinmarketcap_data, icos: [ico_currencies: [:currency]]])

        _ ->
          Repo.all(query)
      end

    {:ok, projects}
  end

  def eth_balance(%Project{id: id}, _args, resolution, only_project_transparency \\ nil) do
    only_project_transparency =
      case only_project_transparency do
        nil ->
          get_parent_args(resolution)
          |> Map.get(:only_project_transparency, false)

        value ->
          value
      end

    batch({__MODULE__, :eth_balances_by_id, only_project_transparency}, id, fn batch_results ->
      {:ok, Map.get(batch_results, id)}
    end)
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

    Map.new(balances, fn balance -> {balance.project_id, balance.balance} end)
  end

  def btc_balance(%Project{id: id}, _args, resolution, only_project_transparency \\ nil) do
    only_project_transparency =
      case only_project_transparency do
        nil ->
          get_parent_args(resolution)
          |> Map.get(:only_project_transparency, false)

        value ->
          value
      end

    batch({__MODULE__, :btc_balances_by_id, only_project_transparency}, id, fn batch_results ->
      {:ok, Map.get(batch_results, id)}
    end)
  end

  def btc_balances_by_id(only_project_transparency, project_ids) do
    query =
      from(
        a in ProjectBtcAddress,
        inner_join: wd in LatestBtcWalletData,
        on: wd.address == a.address,
        where:
          a.project_id in ^project_ids and
            (not (^only_project_transparency) or a.project_transparency),
        group_by: a.project_id,
        select: %{project_id: a.project_id, balance: sum(wd.satoshi_balance)}
      )

    balances = Repo.all(query)

    Map.new(balances, fn balance -> {balance.project_id, balance.balance} end)
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

  defp requested_fields(resolution) do
    resolution.definition.selections
    |> Enum.map(&(Map.get(&1, :name) |> String.to_atom()))
    |> Enum.into(%{}, fn field -> {field, true} end)
  end

  defp get_parent_args(resolution) do
    case resolution do
      %{path: [_, %{argument_data: parent_args} | _]} -> parent_args
      _ -> %{}
    end
  end
end
