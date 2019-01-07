defmodule SanbaseWeb.Graphql.Resolvers.ProjectResolver do
  require Logger

  import Ecto.Query
  import Absinthe.Resolution.Helpers, except: [async: 1]
  import SanbaseWeb.Graphql.Helpers.Async

  alias Sanbase.Model.{
    Project,
    LatestCoinmarketcapData,
    MarketSegment,
    Infrastructure,
    ProjectTransparencyStatus,
    Ico
  }

  alias Sanbase.Voting.{Post, Tag}

  alias Sanbase.Prices

  alias Sanbase.Influxdb.Measurement

  alias Sanbase.Repo
  alias SanbaseWeb.Graphql.Helpers.Cache
  alias SanbaseWeb.Graphql.Resolvers.ProjectBalanceResolver

  alias SanbaseWeb.Graphql.ClickhouseDataloader

  def projects_count(_root, _args, _resolution) do
    {:ok,
     %{
       erc20_projects_count: Project.List.erc20_projects_count(),
       currency_projects_count: Project.List.currency_projects_count(),
       projects_count: Project.List.projects_count()
     }}
  end

  def all_projects_project_transparency(_parent, _args, _resolution) do
    projects = Project.List.projects_transparency()
    {:ok, projects}
  end

  def all_projects(_parent, args, _resolution) do
    page = Map.get(args, :page, nil)
    page_size = Map.get(args, :page_size, nil)

    projects =
      if not page_arguments_valid?(page, page_size) do
        Project.List.projects()
      else
        Project.List.projects_page(page, page_size)
      end

    {:ok, projects}
  end

  def all_erc20_projects(_root, args, _resolution) do
    page = Map.get(args, :page, nil)
    page_size = Map.get(args, :page_size, nil)

    erc20_projects =
      if not page_arguments_valid?(page, page_size) do
        Project.List.erc20_projects()
      else
        Project.List.erc20_projects_page(page, page_size)
      end

    {:ok, erc20_projects}
  end

  def all_currency_projects(_root, args, _resolution) do
    page = Map.get(args, :page, nil)
    page_size = Map.get(args, :page_size, nil)

    currency_projects =
      if not page_arguments_valid?(page, page_size) do
        Project.List.currency_projects()
      else
        Project.List.currency_projects_page(page, page_size)
      end

    {:ok, currency_projects}
  end

  def project(_parent, %{id: id}, _resolution) do
    case Project.by_id(id) do
      nil ->
        {:error, "Project with id '#{id}' not found."}

      project ->
        project =
          project
          |> Repo.preload([:latest_coinmarketcap_data, icos: [ico_currencies: [:currency]]])

        {:ok, project}
    end
  end

  def slug(%Project{coinmarketcap_id: coinmarketcap_id}, _, _), do: {:ok, coinmarketcap_id}

  def project_by_slug(_parent, %{slug: slug}, _resolution) do
    case Project.by_slug(slug) do
      nil ->
        {:error, "Project with slug '#{slug}' not found."}

      project ->
        project =
          project
          |> Repo.preload([:latest_coinmarketcap_data, icos: [ico_currencies: [:currency]]])

        {:ok, project}
    end
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
    {:ok, price_usd |> float_or_nil()}
  end

  def price_usd(_parent, _args, _resolution), do: {:ok, nil}

  def price_btc(
        %Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{price_btc: price_btc}},
        _args,
        _resolution
      ) do
    {:ok, price_btc |> float_or_nil()}
  end

  def price_btc(_parent, _args, _resolution), do: {:ok, nil}

  def volume_usd(
        %Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{volume_usd: volume_usd}},
        _args,
        _resolution
      ) do
    {:ok, volume_usd |> float_or_nil()}
  end

  def volume_usd(_parent, _args, _resolution), do: {:ok, nil}

  def volume_change_24h(%Project{id: id} = project, _args, _resolution) do
    async(Cache.func(fn -> calculate_volume_change_24h(project) end, {:volume_change_24h, id}))
  end

  defp calculate_volume_change_24h(%Project{} = project) do
    measurement_name = Measurement.name_from(project)
    yesterday = Timex.shift(Timex.now(), days: -1)
    the_other_day = Timex.shift(Timex.now(), days: -2)

    with {:ok, [[_dt, today_vol]]} <-
           Prices.Store.fetch_mean_volume(measurement_name, yesterday, Timex.now()),
         {:ok, [[_dt, yesterday_vol]]} <-
           Prices.Store.fetch_mean_volume(measurement_name, the_other_day, yesterday),
         true <- yesterday_vol > 0 do
      {:ok, (today_vol - yesterday_vol) * 100 / yesterday_vol}
    else
      _ ->
        {:ok, nil}
    end
  end

  def average_github_activity(%Project{id: id} = project, %{days: days} = args, _resolution) do
    async(
      Cache.func(
        fn -> calculate_average_github_activity(project, args) end,
        {:average_github_activity, id, days}
      )
    )
  end

  defp calculate_average_github_activity(%Project{} = project, %{days: days}) do
    with {:ok, organization} <- Project.github_organization(project) do
      month_ago = Timex.shift(Timex.now(), days: -days)

      case Sanbase.Clickhouse.Github.total_github_activity(organization, month_ago, Timex.now()) do
        {:ok, total_activity} ->
          {:ok, total_activity / days}

        _ ->
          {:ok, 0}
      end
    else
      {:error, {:github_link_error, error}} ->
        {:ok, nil}

      error ->
        Logger.error(
          "Cannot fetch github activity for #{Project.describe(project)}. Reason: #{
            inspect(error)
          }"
        )

        {:error, "Cannot fetch github activity for #{Project.describe(project)}"}
    end
  rescue
    e ->
      Logger.error(
        "Exception raised while calculating average github activity. Reason: #{inspect(e)}"
      )

      {:ok, nil}
  end

  def average_dev_activity(%Project{} = project, %{days: days}, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(ClickhouseDataloader, :average_dev_activity, %{
      project: project,
      from: Timex.shift(Timex.now(), days: -days),
      to: Timex.now(),
      days: days
    })
    |> on_load(&average_dev_activity_from_loader(&1, project))
  end

  def average_dev_activity_from_loader(loader, project) do
    with {:ok, organization} <- Project.github_organization(project) do
      average_dev_activity =
        loader
        |> Dataloader.get(ClickhouseDataloader, :average_dev_activity, organization)

      {:ok, average_dev_activity}
    else
      _ -> {:ok, nil}
    end
  end

  def marketcap_usd(
        %Project{
          latest_coinmarketcap_data: %LatestCoinmarketcapData{market_cap_usd: market_cap_usd}
        },
        _args,
        _resolution
      ) do
    {:ok, market_cap_usd |> float_or_nil()}
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
        %Project{
          total_supply: total_supply,
          latest_coinmarketcap_data: %LatestCoinmarketcapData{total_supply: cmc_total_supply}
        },
        _args,
        _resolution
      ) do
    {:ok, cmc_total_supply || total_supply}
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

  @doc """
  Return the main sale price, which is the maximum token_usd_ico_price from all icos of a project
  """
  def ico_price(%Project{id: id}, _args, _resolution) do
    ico_with_max_price =
      Project
      |> Repo.get(id)
      |> Repo.preload([:icos])
      |> Map.get(:icos)
      |> Enum.reject(fn ico -> is_nil(ico.token_usd_ico_price) end)
      |> Enum.map(fn ico ->
        %Ico{ico | token_usd_ico_price: Decimal.to_float(ico.token_usd_ico_price)}
      end)
      |> Enum.max_by(fn ico -> ico.token_usd_ico_price end, fn -> nil end)

    case ico_with_max_price do
      %Ico{token_usd_ico_price: ico_price} -> {:ok, ico_price}
      nil -> {:ok, nil}
    end
  end

  def price_to_book_ratio(%Project{} = project, _args, %{context: %{loader: loader}}) do
    loader
    |> ProjectBalanceResolver.usd_balance_loader(project)
    |> on_load(fn loader ->
      with {:ok, usd_balance} <- ProjectBalanceResolver.usd_balance_from_loader(loader, project),
           {:ok, market_cap} <- marketcap_usd(project, nil, nil),
           false <- is_nil(usd_balance) || is_nil(market_cap),
           false <- usd_balance <= 0.001 do
        {:ok, market_cap / usd_balance}
      else
        _ ->
          {:ok, nil}
      end
    end)
  end

  def signals(%Project{} = project, _args, %{context: %{loader: loader}}) do
    loader
    |> ProjectBalanceResolver.usd_balance_loader(project)
    |> on_load(fn loader ->
      with {:ok, usd_balance} <- ProjectBalanceResolver.usd_balance_from_loader(loader, project),
           {:ok, market_cap} <- marketcap_usd(project, nil, nil),
           false <- is_nil(usd_balance) || is_nil(market_cap),
           true <- usd_balance > market_cap do
        {:ok,
         [
           %{
             name: "balance_bigger_than_mcap",
             description: "The balance of the project is bigger than its market capitalization"
           }
         ]}
      else
        _ ->
          {:ok, []}
      end
    end)
  end

  @doc ~s"""
  Returns the combined data for all projects in the slugs list.
  The result is a list of data points with a datetime. For each datetime the marketcap
  and volume are the sum of all marketcaps and volumes of the projects for that date
  """
  def combined_history_stats(
        _,
        %{slugs: slugs, from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, measurement_names_map} <- Measurement.names_from_slugs(slugs),
         measurement_names <- measurement_names_map |> Enum.map(fn {k, _v} -> k end),
         {:ok, result} <-
           Prices.Store.fetch_combined_mcap_volume(measurement_names, from, to, interval) do
      {:ok, result}
    else
      error ->
        error_msg = "Cannot get combined history stats for a list of slugs."
        Logger.error(error_msg <> " Reason: #{inspect(error)}")
        {:error, error_msg}
    end
  end

  def related_posts(%Project{ticker: ticker} = _project, _args, _resolution) when is_nil(ticker),
    do: {:ok, []}

  def related_posts(%Project{ticker: ticker} = _project, _args, _resolution) do
    Cache.func(fn -> fetch_posts_by_ticker(ticker) end, {:related_posts, ticker}).()
  end

  defp fetch_posts_by_ticker(ticker) do
    query =
      from(
        p in Post,
        join: pt in "posts_tags",
        on: p.id == pt.post_id,
        join: t in Tag,
        on: t.id == pt.tag_id,
        where: t.name == ^ticker
      )

    {:ok, Repo.all(query)}
  end

  # Calling Decimal.to_float/1 with `nil` crashes the process
  defp float_or_nil(nil), do: nil
  defp float_or_nil(num), do: Decimal.to_float(num)

  defp page_arguments_valid?(page, page_size) when is_integer(page) and is_integer(page_size) do
    if page > 0 and page_size > 0 do
      true
    else
      false
    end
  end

  defp page_arguments_valid?(_, _), do: false
end
