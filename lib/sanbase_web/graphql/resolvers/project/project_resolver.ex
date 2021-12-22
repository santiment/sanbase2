defmodule SanbaseWeb.Graphql.Resolvers.ProjectResolver do
  require Logger

  import Sanbase.Utils.ErrorHandling, only: [handle_graphql_error: 3]
  import Absinthe.Resolution.Helpers, except: [async: 1]
  import SanbaseWeb.Graphql.Helpers.Async

  alias Sanbase.Model.{
    Project,
    LatestCoinmarketcapData
  }

  alias Sanbase.Insight.Post
  alias SanbaseWeb.Graphql.Cache
  alias SanbaseWeb.Graphql.SanbaseDataloader

  def available_queries(%Project{} = project, _args, _resolution) do
    {:ok, Project.AvailableQueries.get(project)}
  end

  def project(_parent, %{id: id}, _resolution) do
    case Project.by_id(id) do
      nil ->
        {:error, "Project with id '#{id}' not found."}

      project ->
        {:ok, project}
    end
  end

  def project_by_slug(_parent, %{slug: slug}, _resolution), do: get_project_by_slug(slug)
  def project_by_slug(_parent, _args, %{source: %{slug: slug}}), do: get_project_by_slug(slug)

  defp get_project_by_slug(nil), do: {:ok, nil}

  defp get_project_by_slug(slug) do
    case Project.by_slug(slug) do
      nil ->
        {:ok, nil}

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
    |> on_load(fn loader ->
      infrastructure =
        Dataloader.get(loader, SanbaseDataloader, :infrastructure, infrastructure_id)

      {:ok, infrastructure}
    end)
  end

  def traded_on_exchanges(%Project{slug: slug}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :traded_on_exchanges, slug)
    |> on_load(fn loader ->
      exchanges = Dataloader.get(loader, SanbaseDataloader, :traded_on_exchanges, slug)
      {:ok, exchanges}
    end)
  end

  def traded_on_exchanges_count(%Project{slug: slug}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :traded_on_exchanges_count, slug)
    |> on_load(fn loader ->
      count = Dataloader.get(loader, SanbaseDataloader, :traded_on_exchanges_count, slug)

      {:ok, count}
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
    {:ok, price_usd |> Sanbase.Math.to_float()}
  end

  def price_usd(_parent, _args, _resolution), do: {:ok, nil}

  def price_btc(
        %Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{price_btc: price_btc}},
        _args,
        _resolution
      ) do
    {:ok, price_btc |> Sanbase.Math.to_float()}
  end

  def price_btc(_parent, _args, _resolution), do: {:ok, nil}

  def price_eth(
        %Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{price_usd: price_usd}},
        _args,
        _resolution
      ) do
    project_ethereum =
      Sanbase.Cache.get_or_store(
        {__MODULE__, :project_by_slug, "ethereum"} |> Sanbase.Cache.hash(),
        fn -> Project.by_slug("ethereum") end
      )

    case project_ethereum do
      %Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{price_usd: price_eth_in_usd}} ->
        price_eth_in_usd = Sanbase.Math.to_float(price_eth_in_usd, nil)

        if price_eth_in_usd != nil && price_eth_in_usd != 0 do
          {:ok, Sanbase.Math.to_float(price_usd) / Sanbase.Math.to_float(price_eth_in_usd)}
        else
          {:ok, nil}
        end

      _ ->
        {:ok, nil}
    end
  end

  def price_eth(_parent, _args, _resolution), do: {:ok, nil}

  def volume_usd(
        %Project{latest_coinmarketcap_data: %LatestCoinmarketcapData{volume_usd: volume_usd}},
        _args,
        _resolution
      ) do
    {:ok, volume_usd |> Sanbase.Math.to_float()}
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
      |> Dataloader.get(SanbaseDataloader, :volume_change_24h, project.slug)

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

  # Private functions

  defp trending_projects() do
    Cache.wrap(
      fn ->
        case Sanbase.SocialData.TrendingWords.get_currently_trending_projects(10) do
          {:ok, data} -> {:ok, Enum.map(data, & &1.slug)}
          {:error, error} -> {:error, error}
        end
      end,
      :currently_trending_projects
    ).()
  end

  defp calculate_average_github_activity(%Project{} = project, %{days: days}) do
    case Project.github_organizations(project) do
      {:ok, organizations} ->
        month_ago = Timex.shift(Timex.now(), days: -days)

        case Sanbase.Clickhouse.Github.total_github_activity(
               organizations,
               month_ago,
               Timex.now()
             ) do
          {:ok, organizations_activity_map} ->
            total_activity = organizations_activity_map |> Map.values() |> Enum.sum()
            {:ok, total_activity / days}

          _ ->
            {:ok, 0}
        end

      {:error, error} ->
        {:error, handle_graphql_error("average github activity", project.slug, error)}
    end
  rescue
    e ->
      Logger.error(
        "Exception raised while calculating average github activity. Reason: #{inspect(e)}"
      )

      {:ok, nil}
  end

  def average_dev_activity(%Project{} = project, %{days: days}, %{context: %{loader: loader}}) do
    data = %{project: project, days: days}

    loader
    |> Dataloader.load(
      SanbaseDataloader,
      :average_dev_activity,
      data
    )
    |> on_load(&average_dev_activity_from_loader(&1, data))
  end

  def average_dev_activity_from_loader(loader, data) do
    %{project: project, days: days} = data

    case Project.github_organizations(project) do
      {:ok, orgs} when is_list(orgs) and orgs != [] ->
        average_dev_activity = average_dev_activity_per_org(loader, orgs, days)
        values = for {:ok, val} <- average_dev_activity, is_number(val), do: val

        if Enum.member?(values, &match?({:error, _}, &1)) do
          {:nocache, {:ok, Enum.sum(values)}}
        else
          {:ok, Enum.sum(values)}
        end

      _ ->
        {:ok, nil}
    end
  end

  defp average_dev_activity_per_org(loader, organizations, days) do
    dev_activity_map =
      loader
      |> Dataloader.get(SanbaseDataloader, :average_dev_activity, days) ||
        %{}

    organizations
    |> Enum.map(fn org ->
      dev_activity_map
      |> Map.get(org)
      |> case do
        value when is_number(value) -> {:ok, value}
        _ -> {:error, :nodata}
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
    {:ok, market_cap_usd |> Sanbase.Math.to_float()}
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

  def price_to_book_ratio(_root, _args, _resolution) do
    # Note: Deprecated
    {:ok, nil}
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
    case Sanbase.Price.combined_marketcap_and_volume(slugs, from, to, interval) do
      {:ok, result} ->
        {:ok, result}

      error ->
        error_msg = "Cannot get combined history stats for a list of slugs."
        Logger.error(error_msg <> " Reason: #{inspect(error)}")
        {:error, error_msg}
    end
  end

  @spec related_posts(Sanbase.Model.Project.t(), any, any) :: any
  def related_posts(%Project{ticker: ticker} = _project, _args, _resolution) when is_nil(ticker),
    do: {:ok, []}

  def related_posts(%Project{ticker: ticker} = _project, _args, _resolution) do
    Cache.wrap(fn -> fetch_posts_by_ticker(ticker) end, {:related_posts, ticker}).()
  end

  # Private functions

  defp fetch_posts_by_ticker(ticker) do
    posts = Post.public_insights_by_tags([ticker])
    {:ok, posts}
  end
end
