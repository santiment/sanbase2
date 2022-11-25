defmodule SanbaseWeb.Graphql.ProjectTypes do
  use Absinthe.Schema.Notation

  import Absinthe.Resolution.Helpers

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1, cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.{
    ClickhouseResolver,
    ProjectResolver,
    ProjectSignalsResolver,
    ProjectMetricsResolver,
    ProjectBalanceResolver,
    ProjectTransfersResolver,
    IcoResolver,
    TwitterResolver
  }

  alias Sanbase.Project
  alias SanbaseWeb.Graphql.SanbaseRepo
  alias SanbaseWeb.Graphql.Complexity
  alias SanbaseWeb.Graphql.Middlewares.AccessControl

  enum :operator_name do
    value(:less_than)
    value(:greater_than)
    value(:greater_than_or_equal_to)
    value(:less_than_or_equal_to)
    value(:inside_channel)
    value(:inside_channel_inclusive)
    value(:inside_channel_exclusive)
    value(:outside_channel_inclusive)
    value(:outside_channel_exclusive)
  end

  enum :direction_type do
    value(:asc)
    value(:desc)
  end

  enum :filters_combinator do
    value(:and)
    value(:or)
  end

  input_object :project_pagination_input_object do
    field(:page, non_null(:integer))
    field(:page_size, non_null(:integer))
  end

  input_object :project_filter_input_object do
    field(:name, :string)
    field(:args, :json)
    field(:metric, :string)
    field(:from, :datetime)
    field(:to, :datetime)
    field(:dynamic_from, :interval_or_now)
    field(:dynamic_to, :interval_or_now)
    field(:aggregation, :aggregation, default_value: nil)
    field(:operator, :operator_name)
    field(:threshold, :float)
  end

  input_object :project_order_input_object do
    field(:metric, non_null(:string))
    field(:from, non_null(:datetime))
    field(:to, non_null(:datetime))
    field(:aggregation, :aggregation, default_value: nil)
    field(:direction, non_null(:direction_type))
  end

  input_object :base_projects_input_object do
    field(:watchlist_id, :integer)
    field(:watchlist_slug, :string)
    field(:slugs, list_of(:string))
  end

  input_object :projects_selector_input_object do
    field(:base_projects, list_of(:base_projects_input_object))
    field(:filters, list_of(:project_filter_input_object))
    field(:filters_combinator, :filters_combinator, default_value: :and)
    field(:order_by, :project_order_input_object)
    field(:pagination, :project_pagination_input_object)
  end

  input_object :aggregated_timeseries_data_selector_input_object do
    field(:label, :string)
    field(:labels, list_of(:string))
    field(:owner, :string)
    field(:owners, list_of(:string))
    field(:holders_count, :integer)
    field(:source, :string)
  end

  object :metric_anomalies do
    field(:metric, :string)
    field(:anomalies, list_of(:string))
  end

  object :project_tag do
    field(:name, non_null(:string))
    field(:type, :string)
  end

  object :projects_object_stats do
    field(:projects_count, non_null(:integer))
  end

  object :projects_object do
    field(:projects, list_of(:project))
    field(:stats, :projects_object_stats)
  end

  # Includes all available fields
  @desc ~s"""
  A type fully describing a project.
  """
  object :project do
    @desc ~s"""
    Returns a list of available signals. Every one of the signals in the list
    can be passed as the `metric` argument of the `getMetric` query.

    For example, any of of the signals from the query:
    ```
    {
      projectBySlug(slug: "ethereum"){ availableSignals }
    }
    ```
    can be used like this:
    ```
    {
      getSignal(signal: "<signal>"){
        timeseriesData(
          slug: "ethereum"
          from: "2019-01-01T00:00:00Z"
          to: "2019-02-01T00:00:00Z"
          interval: "1d"){
            datetime
            value
          }
      }
    ```
    """

    field :available_signals, list_of(:string) do
      cache_resolve(&ProjectSignalsResolver.available_signals/3, ttl: 600)
    end

    @desc ~s"""
    Returns a list of available metrics. Every one of the metrics in the list
    can be passed as the `metric` argument of the `getMetric` query.

    For example, any of of the metrics from the query:
    ```
    {
      projectBySlug(slug: "ethereum"){ availableMetrics }
    }
    ```
    can be used like this:
    ```
    {
      getMetric(metric: "<metric>"){
        timeseriesData(
          slug: "ethereum"
          from: "2019-01-01T00:00:00Z"
          to: "2019-02-01T00:00:00Z"
          interval: "1d"){
            datetime
            value
          }
      }
    }
    ```
    or
    ```
    {
      getMetric(metric: "<metric>"){
        histogramData(
          slug: "ethereum"
          from: "2019-01-01T00:00:00Z"
          to: "2019-02-01T00:00:00Z"
          interval: "1d"
          limit: 50){
            datetime
            value
          }
      }
    }
    ```

    The breakdown of the metrics into those fetchable by `timeseriesData` and
    `histogramData` is fetchable by the following fields:
    ```
    {
      projectBySlug(slug: "ethereum"){
        availableTimeseriesMetrics
        availableHistogramMetrics
      }
    }
    ```
    """
    field :available_metrics, list_of(:string) do
      cache_resolve(&ProjectMetricsResolver.available_metrics/3, ttl: 300)
    end

    @desc ~s"""
    Returns a subset of the availableMetrics that are fetchable by getMetric's
    timeseriesData
    ```
    {
      getMetric(metric: "<metric>"){
        timeseriesData(
          slug: "ethereum"
          from: "2019-01-01T00:00:00Z"
          to: "2019-02-01T00:00:00Z"
          interval: "1d"){
            datetime
            value
          }
      }
    }
    ```
    """
    field :available_timeseries_metrics, list_of(:string) do
      cache_resolve(&ProjectMetricsResolver.available_timeseries_metrics/3, ttl: 300)
    end

    @desc ~s"""
    Returns a subset of the availableMetrics that are fetchable by getMetric's
    histogramDAta
    ```
    {
      getMetric(metric: "<metric>"){
        histogramData(
          slug: "ethereum"
          from: "2019-01-01T00:00:00Z"
          to: "2019-02-01T00:00:00Z"
          interval: "1d"
          limit: 50){
            datetime
            value
          }
      }
    }
    ```
    """
    field :available_histogram_metrics, list_of(:string) do
      cache_resolve(&ProjectMetricsResolver.available_histogram_metrics/3, ttl: 300)
    end

    field :available_table_metrics, list_of(:string) do
      cache_resolve(&ProjectMetricsResolver.available_table_metrics/3, ttl: 300)
    end

    field :traded_on_exchanges, list_of(:string) do
      cache_resolve(&ProjectResolver.traded_on_exchanges/3)
    end

    field :traded_on_exchanges_count, :integer do
      cache_resolve(&ProjectResolver.traded_on_exchanges_count/3)
    end

    @desc ~s"""
    Returns a list of GraphQL queries that have data for the given slug.

    For example, any of the queries returned from the query:
    ```
    {
      projectBySlug(slug: "ethereum"){ availableQueries }
    }
    ```
    can be executed with "ethereum" slug as parameter and it will have data.
    `devActivity` query will be part of the result if that project has a known
    github link. So the following query will have data:
    ```
    {
      devActivity(
        slug: "ethereum"
        from: "2019-01-01T00:00:00Z"
        to: "2019-02-01T00:00:00Z"
        interval: "1d"){
          datetime
          activity
        }
    }
    ```
    """
    field :available_queries, list_of(:string) do
      cache_resolve(&ProjectResolver.available_queries/3, ttl: 120)
    end

    field :aggregated_timeseries_data, :float do
      arg(:selector, :aggregated_timeseries_data_selector_input_object)
      arg(:metric, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:aggregation, :aggregation, default_value: nil)
      arg(:include_incomplete_data, :boolean, default_value: false)
      arg(:caching_params, :caching_params_input_object)

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)

      cache_resolve(&ProjectMetricsResolver.aggregated_timeseries_data/3,
        ttl: 120,
        max_ttl_offset: 60
      )
    end

    field(:id, non_null(:id))
    field(:name, non_null(:string))
    field(:slug, :string)
    field(:ticker, :string)
    field(:logo_url, :string)
    field(:dark_logo_url, :string)
    field(:website_link, :string)
    field(:email, :string)
    field(:btt_link, :string)
    field(:facebook_link, :string)
    field(:github_link, :string)
    field(:reddit_link, :string)
    field(:twitter_link, :string)
    field(:whitepaper_link, :string)
    field(:blog_link, :string)
    field(:telegram_chat_id, :integer)
    field(:slack_link, :string)
    field(:discord_link, :string)
    field(:linkedin_link, :string)
    field(:telegram_link, :string)
    field(:token_address, :string)
    field(:team_token_wallet, :string)
    field(:description, :string)
    field(:long_description, :string)
    field(:token_decimals, :integer)

    field :main_contract_address, :string do
      cache_resolve(
        dataloader(SanbaseRepo, :contract_addresses,
          callback: fn contract_addresses, _project, _args ->
            case contract_addresses do
              [_ | _] ->
                main = Project.ContractAddress.list_to_main_contract_address(contract_addresses)
                {:ok, main.address}

              _ ->
                {:ok, nil}
            end
          end
        ),
        fun_name: :project_main_contract_address
      )
    end

    field :contract_addresses, list_of(:contract_address) do
      cache_resolve(
        dataloader(SanbaseRepo),
        fun_name: :project_contract_addresses
      )
    end

    field :eth_addresses, list_of(:eth_address) do
      cache_resolve(
        dataloader(SanbaseRepo),
        fun_name: :eth_addresses_resolver_fun
      )
    end

    field :social_volume_query, :string do
      cache_resolve(
        dataloader(SanbaseRepo, :social_volume_query,
          callback: fn
            nil, project, _args ->
              {:ok, Project.SocialVolumeQuery.default_query(project)}

            svq, _project, _args ->
              case svq.query do
                query when query in [nil, ""] -> {:ok, svq.autogenerated_query}
                _ -> {:ok, svq.query}
              end
          end
        ),
        fun_name: :social_volume_query
      )
    end

    field :source_slug_mappings, list_of(:source_slug_mapping) do
      cache_resolve(
        dataloader(SanbaseRepo, :source_slug_mappings,
          callback: fn query, _project, _args -> {:ok, query} end
        ),
        fun_name: :source_slug_mappings
      )
    end

    field :market_segment, :string do
      # Introduce a different function name so it does not share cache with the
      # :market_segments as they query the same data
      cache_resolve(
        dataloader(SanbaseRepo, :market_segments,
          callback: fn query, _project, _args ->
            {:ok, query |> Enum.map(& &1.name) |> List.first()}
          end
        ),
        fun_name: :market_segment
      )
    end

    field :market_segments, list_of(:string) do
      cache_resolve(
        dataloader(SanbaseRepo, :market_segments,
          callback: fn query, _project, _args ->
            {:ok, query |> Enum.map(& &1.name)}
          end
        ),
        fun_name: :market_segments
      )
    end

    field :tags, list_of(:project_tag) do
      cache_resolve(
        dataloader(SanbaseRepo, :market_segments,
          callback: fn query, _project, _args ->
            {:ok, query}
          end,
          fun_name: :project_market_segment_tags
        )
      )
    end

    field :is_trending, :boolean do
      cache_resolve(&ProjectResolver.is_trending/3)
    end

    field :github_links, list_of(:string) do
      cache_resolve(&ProjectResolver.github_links/3)
    end

    field :related_posts, list_of(:post) do
      cache_resolve(&ProjectResolver.related_posts/3)
    end

    field :infrastructure, :string do
      cache_resolve(&ProjectResolver.infrastructure/3)
    end

    field :eth_balance, :float do
      cache_resolve(&ProjectBalanceResolver.eth_balance/3)
    end

    field :btc_balance, :float do
      deprecate("The field btc_balance is deprecated")
      cache_resolve(&ProjectBalanceResolver.btc_balance/3)
    end

    field :usd_balance, :float do
      cache_resolve(&ProjectBalanceResolver.usd_balance/3)
    end

    field :funds_raised_icos, list_of(:currency_amount) do
      cache_resolve(&ProjectResolver.funds_raised_icos/3,
        ttl: 600,
        max_ttl_offset: 600
      )
    end

    field :roi_usd, :decimal do
      cache_resolve(&ProjectResolver.roi_usd/3)
    end

    field :coinmarketcap_id, :string do
      resolve(fn %Project{slug: slug}, _, _ -> {:ok, slug} end)
    end

    field :symbol, :string do
      resolve(&ProjectResolver.symbol/3)
    end

    field :rank, :integer do
      resolve(&ProjectResolver.rank/3)
    end

    field :price_usd, :float do
      resolve(&ProjectResolver.price_usd/3)
    end

    field :price_btc, :float do
      resolve(&ProjectResolver.price_btc/3)
    end

    field :price_eth, :float do
      resolve(&ProjectResolver.price_eth/3)
    end

    field :volume_usd, :float do
      resolve(&ProjectResolver.volume_usd/3)
    end

    field :volume_change24h, :float do
      cache_resolve(&ProjectResolver.volume_change_24h/3, ttl: 300)
    end

    field :average_dev_activity, :float do
      description("Average dev activity for the last `days` days")
      arg(:days, :integer, default_value: 30)

      cache_resolve(&ProjectResolver.average_dev_activity/3, ttl: 300)
    end

    field :average_github_activity, :float do
      description("Average github activity for the last `days` days")
      arg(:days, :integer, default_value: 30)

      cache_resolve(&ProjectResolver.average_github_activity/3, ttl: 300)
    end

    field :twitter_data, :twitter_data do
      cache_resolve(&TwitterResolver.twitter_data/3, ttl: 300)
    end

    field :marketcap_usd, :float do
      resolve(&ProjectResolver.marketcap_usd/3)
    end

    field :available_supply, :decimal do
      resolve(&ProjectResolver.available_supply/3)
    end

    field :total_supply, :decimal do
      resolve(&ProjectResolver.total_supply/3)
    end

    field :percent_change1h, :decimal do
      resolve(&ProjectResolver.percent_change_1h/3)
    end

    field :percent_change24h, :decimal do
      resolve(&ProjectResolver.percent_change_24h/3)
    end

    field :percent_change7d, :decimal do
      resolve(&ProjectResolver.percent_change_7d/3)
    end

    field :funds_raised_usd_ico_end_price, :float do
      cache_resolve(&ProjectResolver.funds_raised_usd_ico_end_price/3,
        ttl: 600,
        max_ttl_offset: 600
      )
    end

    field :funds_raised_eth_ico_end_price, :float do
      cache_resolve(&ProjectResolver.funds_raised_eth_ico_end_price/3,
        ttl: 300,
        max_ttl_offset: 300
      )
    end

    field :funds_raised_btc_ico_end_price, :float do
      cache_resolve(&ProjectResolver.funds_raised_btc_ico_end_price/3,
        ttl: 300,
        max_ttl_offset: 300
      )
    end

    field :initial_ico, :ico do
      cache_resolve(&ProjectResolver.initial_ico/3, ttl: 300, max_ttl_offset: 300)
    end

    field(:icos, list_of(:ico), resolve: dataloader(SanbaseRepo))

    field :ico_price, :float do
      cache_resolve(&ProjectResolver.ico_price/3)
    end

    field :price_to_book_ratio, :float do
      deprecate("The field price_to_book_ratio is deprecated")
      cache_resolve(&ProjectResolver.price_to_book_ratio/3)
    end

    @desc "Total ETH spent from the project's team wallets for the last `days`"
    field :eth_spent, :float do
      arg(:days, :integer, default_value: 30)

      cache_resolve(&ProjectTransfersResolver.eth_spent/3,
        ttl: 300,
        max_ttl_offset: 240
      )
    end

    @desc "ETH spent for each `interval` from the project's team wallet and time period"
    field :eth_spent_over_time, list_of(:eth_spent_data) do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)

      cache_resolve(&ProjectTransfersResolver.eth_spent_over_time/3,
        ttl: 600,
        max_ttl_offset: 240
      )
    end

    @desc "Top ETH transactions for project's team wallets"
    field :eth_top_transactions, list_of(:transaction) do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:transaction_type, :transaction_type, default_value: :all)
      arg(:limit, :integer, default_value: 10)

      complexity(&Complexity.from_to_interval/3)
      cache_resolve(&ProjectTransfersResolver.eth_top_transfers/3)
    end

    @desc "Top transactions for the token of a given project"
    field :token_top_transactions, list_of(:transaction) do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:limit, :integer, default_value: 10)
      arg(:excluded_addresses, list_of(:string))

      complexity(&Complexity.from_to_interval/3)
      cache_resolve(&ProjectTransfersResolver.token_top_transfers/3)
    end

    @desc "Average daily active addresses for a ERC20 project or Ethereum and given time period"
    field :average_daily_active_addresses, :float do
      arg(:from, :datetime)
      arg(:to, :datetime)

      cache_resolve(&ClickhouseResolver.average_daily_active_addresses/3,
        ttl: 600,
        max_ttl_offset: 600
      )
    end
  end

  object :contract_address do
    field(:address, non_null(:string))
    field(:decimals, :integer)
    field(:label, :string)
    field(:description, :string)
    field(:inserted_at, :datetime)
    field(:updated_at, :datetime)
  end

  object :source_slug_mapping do
    field(:source, non_null(:string))
    field(:slug, non_null(:string))
  end

  object :eth_address do
    field(:address, non_null(:string))

    field :balance, :float do
      cache_resolve(&ProjectBalanceResolver.eth_address_balance/3)
    end
  end

  object :ico do
    field(:id, non_null(:id))
    field(:start_date, :date)
    field(:end_date, :date)
    field(:token_usd_ico_price, :decimal)
    field(:token_eth_ico_price, :decimal)
    field(:token_btc_ico_price, :decimal)
    field(:tokens_issued_at_ico, :decimal)
    field(:tokens_sold_at_ico, :decimal)

    field :funds_raised_usd_ico_end_price, :float do
      resolve(&IcoResolver.funds_raised_usd_ico_end_price/3)
    end

    field :funds_raised_eth_ico_end_price, :float do
      resolve(&IcoResolver.funds_raised_eth_ico_end_price/3)
    end

    field :funds_raised_btc_ico_end_price, :float do
      resolve(&IcoResolver.funds_raised_btc_ico_end_price/3)
    end

    field(:minimal_cap_amount, :decimal)
    field(:maximal_cap_amount, :decimal)
    field(:contract_block_number, :integer)
    field(:contract_abi, :string)
    field(:comments, :string)

    field :cap_currency, :string do
      resolve(&IcoResolver.cap_currency/3)
    end

    field :funds_raised, list_of(:currency_amount) do
      resolve(&IcoResolver.funds_raised/3)
    end
  end

  object :ico_with_eth_contract_info do
    field(:id, non_null(:id))
    field(:start_date, :date)
    field(:end_date, :date)
    field(:main_contract_address, :string)
    field(:contract_block_number, :integer)
    field(:contract_abi, :string)
  end

  object :currency_amount do
    field(:currency_code, :string)
    field(:amount, :decimal)
  end

  object :eth_spent_data do
    field(:datetime, non_null(:datetime))
    field(:eth_spent, :float)
  end

  object :projects_count do
    field(:erc20_projects_count, non_null(:integer))
    field(:currency_projects_count, non_null(:integer))
    field(:projects_count, non_null(:integer))
  end
end
