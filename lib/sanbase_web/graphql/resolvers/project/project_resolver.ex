defmodule SanbaseWeb.Graphql.Resolvers.ProjectResolver do
  require Logger

  import Absinthe.Resolution.Helpers, except: [async: 1]
  import SanbaseWeb.Graphql.Helpers.Async

  alias Sanbase.Model.{
    Project,
    LatestCoinmarketcapData
  }

  alias Sanbase.Insight.Post
  alias Sanbase.Prices
  alias Sanbase.Influxdb.Measurement
  alias SanbaseWeb.Graphql.Cache
  alias SanbaseWeb.Graphql.Resolvers.ProjectBalanceResolver
  alias SanbaseWeb.Graphql.SanbaseDataloader

  def available_metrics(%Project{} = project, _args, _resolution) do
    available_metrics = Project.AvailableMetrics.get(project)
    {:ok, available_metrics}
  end

  def projects_count(_root, args, _resolution) do
    min_volume = Map.get(args, :min_volume)

    {:ok,
     %{
       erc20_projects_count: Project.List.erc20_projects_count(min_volume),
       currency_projects_count: Project.List.currency_projects_count(min_volume),
       projects_count: Project.List.projects_count(min_volume)
     }}
  end

  def all_projects_project_transparency(_parent, _args, _resolution) do
    projects = Project.List.projects_transparency()
    {:ok, projects}
  end

  def all_projects(_parent, args, _resolution) do
    page = Map.get(args, :page)
    page_size = Map.get(args, :page_size)
    min_volume = Map.get(args, :min_volume)

    projects =
      if page_arguments_valid?(page, page_size) do
        Project.List.projects_page(page, page_size, min_volume)
      else
        Project.List.projects(min_volume)
      end

    {:ok, projects}
  end

  def all_erc20_projects(_root, args, _resolution) do
    page = Map.get(args, :page)
    page_size = Map.get(args, :page_size)
    min_volume = Map.get(args, :min_volume)

    erc20_projects =
      if page_arguments_valid?(page, page_size) do
        Project.List.erc20_projects_page(page, page_size, min_volume)
      else
        Project.List.erc20_projects(min_volume)
      end

    {:ok, erc20_projects}
  end

  def all_currency_projects(_root, args, _resolution) do
    page = Map.get(args, :page)
    page_size = Map.get(args, :page_size)
    min_volume = Map.get(args, :min_volume)

    currency_projects =
      if page_arguments_valid?(page, page_size) do
        Project.List.currency_projects_page(page, page_size, min_volume)
      else
        Project.List.currency_projects(min_volume)
      end

    {:ok, currency_projects}
  end

  def all_projects_by_function(_root, %{function: function}, _resolution) do
    with {:ok, function} <- Sanbase.WatchlistFunction.cast(function),
         projects when is_list(projects) <- Sanbase.WatchlistFunction.evaluate(function) do
      {:ok, projects}
    end
  end

  def project(_parent, %{id: id}, _resolution) do
    case Project.by_id(id) do
      nil ->
        {:error, "Project with id '#{id}' not found."}

      project ->
        {:ok, project}
    end
  end

  def project_by_slug(_parent, %{slug: slug}, _resolution) do
    case Project.by_slug(slug) do
      nil ->
        {:error, "Project with slug '#{slug}' not found."}

      project ->
        {:ok, project}
    end
  end

  def is_trending(%Project{slug: slug}, _args, _resolution) do
    case trending_projects() do
      {:ok, result} -> {:ok, slug in result}
      _ -> {:nocache, {:ok, false}}
    end
  end

  defp trending_projects() do
    Cache.wrap(
      fn ->
        case Sanbase.SocialData.TrendingWords.get_currently_trending_projects() do
          {:ok, data} -> {:ok, Enum.map(data, & &1.slug)}
          {:error, error} -> {:error, error}
        end
      end,
      :currently_trending_projects
    ).()
  end

  def funds_raised_icos(%Project{} = project, _args, _resolution) do
    funds_raised = Project.funds_raised_icos(project)
    {:ok, funds_raised}
  end

  def infrastructure(%Project{infrastructure_id: nil}, _args, _resolution), do: {:ok, nil}

  def infrastructure(%Project{infrastructure_id: infrastructure_id}, _args, %{
        context: %{loader: loader}
      }) do
    loader
    |> Dataloader.load(SanbaseDataloader, :infrastructure, infrastructure_id)
    |> on_load(&infrastructure_from_loader(&1, infrastructure_id))
  end

  defp infrastructure_from_loader(loader, infrastructure_id) do
    infrastructure =
      loader
      |> Dataloader.get(SanbaseDataloader, :infrastructure, infrastructure_id)

    {:ok, infrastructure}
  end

  def project_transparency_status(
        %Project{project_transparency_status_id: nil},
        _args,
        _resolution
      ),
      do: {:ok, nil}

  def project_transparency_status(
        %Project{project_transparency_status_id: ptsi},
        _args,
        %{context: %{loader: loader}}
      ) do
    loader
    |> Dataloader.load(SanbaseDataloader, :project_transparency_status, ptsi)
    |> on_load(&project_transparency_status_from_loader(&1, ptsi))
  end

  defp project_transparency_status_from_loader(loader, project_transparency_status_id) do
    status =
      loader
      |> Dataloader.get(
        SanbaseDataloader,
        :project_transparency_status,
        project_transparency_status_id
      )

    {:ok, status}
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

  def volume_change_24h(%Project{} = project, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :volume_change_24h, project)
    |> on_load(&volume_change_24h_from_loader(&1, project))
  end

  defp volume_change_24h_from_loader(loader, project) do
    volume_change_24h =
      loader
      |> Dataloader.get(SanbaseDataloader, :volume_change_24h, Measurement.name_from(project))

    {:ok, volume_change_24h}
  end

  def github_links(%Project{} = project, _args, _resolution) do
    {:ok, orgs} = Project.github_organizations(project)
    links = orgs |> Enum.map(&Project.GithubOrganization.organization_to_link/1)
    {:ok, links}
  end

  def average_github_activity(%Project{id: id} = project, %{days: days} = args, _resolution) do
    async(
      Cache.wrap(
        fn -> calculate_average_github_activity(project, args) end,
        {:average_github_activity, id, days}
      )
    )
  end

  defp calculate_average_github_activity(%Project{} = project, %{days: days}) do
    with {:ok, organizations} <- Project.github_organizations(project) do
      month_ago = Timex.shift(Timex.now(), days: -days)

      case Sanbase.Clickhouse.Github.total_github_activity(organizations, month_ago, Timex.now()) do
        {:ok, total_activity} ->
          {:ok, total_activity / days}

        _ ->
          {:ok, 0}
      end
    else
      {:error, {:github_link_error, _error}} ->
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
    |> Dataloader.load(SanbaseDataloader, :average_dev_activity, %{
      project: project,
      from: Timex.shift(Timex.now(), days: -days),
      to: Timex.now(),
      days: days
    })
    |> on_load(&average_dev_activity_from_loader(&1, project))
  end

  def average_dev_activity_from_loader(loader, project) do
    with {:ok, orgs} when is_list(orgs) and orgs != [] <- Project.github_organizations(project) do
      average_dev_activity = average_dev_activity_per_org(loader, orgs)
      values = for {:ok, val} <- average_dev_activity, is_number(val), do: val

      if Enum.member?(values, &match?({:error, _}, &1)) do
        {:nocache, {:ok, Enum.sum(values)}}
      else
        {:ok, Enum.sum(values)}
      end
    else
      _ -> {:ok, nil}
    end
  end

  defp average_dev_activity_per_org(loader, organizations) do
    organizations
    |> Enum.map(fn org ->
      loader
      |> Dataloader.get(SanbaseDataloader, :average_dev_activity, org)
      |> case do
        nil -> {:ok, 0}
        result -> result
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
    {:ok, Project.initial_ico(project)}
  end

  @doc """
  Return the main sale price, which is the maximum token_usd_ico_price from all icos of a project
  """
  def ico_price(%Project{} = project, _args, _resolution) do
    {:ok, Project.ico_price(project)}
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
    Cache.wrap(fn -> fetch_posts_by_ticker(ticker) end, {:related_posts, ticker}).()
  end

  # Private functions

  defp fetch_posts_by_ticker(ticker) do
    posts = Post.public_insights_by_tag(ticker)
    {:ok, posts}
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
