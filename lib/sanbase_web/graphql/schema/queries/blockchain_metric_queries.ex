defmodule SanbaseWeb.Graphql.Schema.BlockchainMetricQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.ClickhouseResolver
  alias SanbaseWeb.Graphql.Resolvers.ExchangeResolver

  alias SanbaseWeb.Graphql.Complexity
  alias SanbaseWeb.Graphql.Middlewares.{AccessControl, BasicAuth}

  object :blockchain_metric_queries do
    @desc ~s"""
    Fetch the flow of funds into and out of an exchange wallet.
    This query returns the difference IN-OUT calculated for each interval.
    """
    field :exchange_funds_flow, list_of(:exchange_funds_flow) do
      # TODO: Remove after migrating sansheets to not use this
      deprecate(~s/Use getMetric(metric: "exchange_balance") instead./)
      meta(access: :restricted)

      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&ClickhouseResolver.exchange_funds_flow/3)
    end

    @desc "Returns what percent of token supply is on exchanges"
    field :percent_of_token_supply_on_exchanges, list_of(:percent_of_token_supply_on_exchanges) do
      meta(access: :restricted)

      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&ClickhouseResolver.percent_of_token_supply_on_exchanges/3)
    end

    @desc """
    Returns used Gas by a blockchain.
    When you send tokens, interact with a contract or do anything else on the blockchain,
    you must pay for that computation. That payment is calculated in Gas.
    """
    field :gas_used, list_of(:gas_used) do
      meta(access: :restricted)

      arg(:slug, :string, default_value: "ethereum")
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&ClickhouseResolver.gas_used/3)
    end

    @desc """
    Returns the first `number_of_holders` top holders for ETH or ERC20 token.

    Arguments description:
    * slug - a string uniquely identifying a project
    * number_of_holders - take top `number_of_holders` into account when calculating.
    * from - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
    * to - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
    """
    field :top_holders, list_of(:top_holders) do
      meta(access: :restricted)

      arg(:slug, non_null(:string))

      arg(:number_of_holders, non_null(:integer),
        deprecate: "pageSize argument should be used instead"
      )

      arg(:page, non_null(:integer), default_value: 1)
      arg(:page_size, non_null(:integer), default_value: 20)
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:owners, list_of(:string))
      arg(:labels, list_of(:string))

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&ClickhouseResolver.top_holders/3)
    end

    @desc """
    Returns the first `number_of_holders` current top holders for ETH or ERC20 token.

    Arguments description:
    * slug - a string uniquely identifying a project
    * page and page_size - choose what top holders to return, sorted in descending order by value
    """
    field :realtime_top_holders, list_of(:top_holders) do
      meta(access: :restricted)

      arg(:slug, non_null(:string))

      arg(:page, non_null(:integer), default_value: 1)
      arg(:page_size, non_null(:integer), default_value: 20)

      middleware(AccessControl)
      cache_resolve(&ClickhouseResolver.realtime_top_holders/3)
    end

    @desc """
    Returns the top holders' percent of total supply - in exchanges, outside exchanges and combined.

    Arguments description:
    * slug - a string uniquely identifying a project
    * number_of_holders - take top `number_of_holders` into account when calculating.
    * from - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
    * to - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
    """
    field :top_holders_percent_of_total_supply, list_of(:top_holders_percent_of_total_supply) do
      meta(access: :restricted)

      arg(:slug, non_null(:string))
      arg(:number_of_holders, non_null(:integer))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&ClickhouseResolver.top_holders_percent_of_total_supply/3)
    end

    @desc ~s"""
    List all exchanges
    """
    field :get_label_based_metric_owners, list_of(:string) do
      meta(access: :free)

      arg(:metric, non_null(:string))
      arg(:slug, :string)

      cache_resolve(&ExchangeResolver.get_label_based_metric_owners/3)
    end

    @desc "List all exchanges"
    field :all_exchanges, list_of(:string) do
      meta(access: :free)

      arg(:slug, non_null(:string))
      arg(:is_dex, :boolean)

      cache_resolve(&ExchangeResolver.all_exchanges/3)
    end

    field :eth_fees_distribution, list_of(:fees_distribution) do
      meta(access: :free)

      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:limit, :integer, default_value: 20)

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&ClickhouseResolver.eth_fees_distribution/3)
    end
  end
end
