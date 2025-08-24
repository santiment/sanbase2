defmodule Sanbase.MCP.DataCatalog do
  @moduledoc "Centralized catalog of available metrics and slugs for MCP tools"

  @available_metrics [
    %{
      name: "price_usd",
      description: "Price in USD for cryptocurrencies",
      unit: "USD"
    },
    %{
      name: "marketcap_usd",
      description: "Total market capitalization in USD",
      unit: "USD"
    },
    %{
      name: "volume_usd",
      description: "Trading volume in USD",
      unit: "USD"
    },
    %{
      name: "price_btc",
      description: "Asset price denominated in BTC",
      unit: "BTC"
    },
    %{
      name: "price_volatility_1d",
      description: "Realized price volatility over 1 day",
      unit: "percent"
    },
    %{
      name: "fully_diluted_valuation_usd",
      description: "Fully diluted valuation in USD",
      unit: "USD"
    },
    %{
      name: "dev_activity",
      description:
        "Development activity events on tracked repositories (commits, PRs, issues, etc.)",
      unit: "count"
    },
    %{
      name: "dev_activity_contributors_count",
      description: "Number of unique developers contributing across tracked repositories",
      unit: "count"
    },
    %{
      name: "github_activity",
      description: "GitHub activity events for the project",
      unit: "count"
    },
    %{
      name: "github_activity_contributors_count",
      description: "Unique GitHub contributors count",
      unit: "count"
    },
    %{
      name: "social_volume_total",
      description: "Total social media mentions and discussions",
      unit: "count"
    },
    %{
      name: "social_dominance_total",
      description: "Share of total crypto social mentions attributed to the asset",
      unit: "percent"
    },
    %{
      name: "sentiment_weighted_total",
      description: "Overall weighted social sentiment score",
      unit: "score"
    },
    %{
      name: "twitter_followers",
      description: "Number of followers on the project's official Twitter/X account",
      unit: "count"
    },
    %{
      name: "daily_active_addresses",
      description: "Daily active addresses",
      unit: "count"
    },
    %{
      name: "transactions_count",
      description: "Number of on-chain transactions",
      unit: "count"
    },
    %{
      name: "transaction_volume",
      description: "On-chain transaction volume in number of coins/tokens",
      unit: "count"
    },
    %{
      name: "transaction_volume_usd",
      description: "On-chain transaction volume in USD",
      unit: "USD"
    },
    %{
      name: "network_growth",
      description: "New addresses that made their first on-chain transaction",
      unit: "count"
    },
    %{
      name: "mvrv_usd",
      description: "Market Value to Realized Value ratio (USD terms)",
      unit: "ratio"
    },
    %{
      name: "supply_on_exchanges",
      description: "Amount of tokens held on exchange addresses",
      unit: "tokens"
    },
    %{
      name: "exchange_inflow_usd",
      description: "USD value of tokens deposited to exchange addresses",
      unit: "USD"
    },
    %{
      name: "exchange_outflow_usd",
      description: "USD value of tokens withdrawn from exchange addresses",
      unit: "USD"
    }
  ]

  @spec get_all_projects() :: list(map())
  def get_all_projects() do
    cache_key = {__MODULE__, :available_slugs} |> Sanbase.Cache.hash()

    {:ok, projects_data} =
      Sanbase.Cache.get_or_store(cache_key, fn ->
        san = Sanbase.Project.by_slug("santiment")

        projects = List.wrap(san) ++ Sanbase.Project.List.projects_page(1, 500)

        projects_data =
          Enum.map(projects, fn p ->
            %{
              name: p.name,
              slug: p.slug,
              ticker: p.ticker,
              description: p.description
            }
          end)

        {:ok, projects_data}
      end)

    projects_data
  end

  def available_slugs() do
    cache_key = {__MODULE__, :available_slugs} |> Sanbase.Cache.hash()

    {:ok, slugs} =
      Sanbase.Cache.get_or_store(cache_key, fn ->
        projects = get_all_projects()
        slugs = Enum.map(projects, & &1.slug)
        {:ok, slugs}
      end)

    slugs
  end

  def available_metrics() do
    @available_metrics
  end

  @doc "Get all available metrics"
  @spec get_all_metrics() :: list(map())
  def get_all_metrics, do: available_metrics()

  @doc "Get all available slugs"
  @spec get_all_slugs() :: list(String.t())
  def get_all_slugs, do: available_slugs()

  @doc "Get metric names only"
  @spec get_metric_names() :: list(String.t())
  def get_metric_names, do: available_metrics() |> Enum.map(& &1.name)

  @doc "Get available metrics for a specific slug"
  def get_available_metrics_for_slug(slug) do
    if valid_slug?(slug) do
      {:ok, all_metrics} = Sanbase.Metric.available_metrics_for_selector(%{slug: slug})

      # Get the intersection of the exposed metrics in the tool and the metrics supported
      # by the asset
      {:ok,
       MapSet.intersection(MapSet.new(all_metrics), MapSet.new(get_metric_names()))
       |> Enum.to_list()}
    else
      {:error, "Slug '#{slug}' not supported or mistyped."}
    end
  end

  @doc "Get available slugs for a specific metric"
  def get_available_slugs_for_metric(metric) do
    if metric in get_metric_names() do
      {:ok, Sanbase.Metric.available_slugs(metric)}
    else
      {:error, "Metric '#{metric}' not supported or mistyped."}
    end
  end

  @doc "Validate if a metric exists"
  def valid_metric?(metric), do: metric in get_metric_names()

  @doc "Validate if a slug exists"
  def valid_slug?(slug), do: slug in available_slugs()

  @doc "Validate metric and slug combination"
  def validate_metric_slug_combination(metric, slug) do
    cond do
      not valid_slug?(slug) ->
        {:error,
         "Slug '#{slug}' not found. Available slugs: #{Enum.join(@available_slugs, ", ")}"}

      not valid_metric?(metric) ->
        {:error,
         "Metric '#{metric}' not found. Available metrics: #{Enum.join(get_metric_names(), ", ")}"}

      true ->
        metric_info = Enum.find(@available_metrics, &(&1.name == metric))
        {:ok, metric_info}
    end
  end
end
