defmodule SanbaseWeb.Graphql.Schema.BlockchainMetricQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.{EtherbiResolver, ClickhouseResolver, ExchangeResolver}

  alias SanbaseWeb.Graphql.Complexity
  alias SanbaseWeb.Graphql.Middlewares.{AccessControl, BasicAuth}

  object :blockchain_metric_queries do
    # STANDART PLAN
    @desc ~s"""
    Fetch burn rate for a project within a given time period, grouped by interval.
    Projects are referred to by a unique identifier (slug).

    Each transaction has an equivalent burn rate record. The burn rate is calculated
    by multiplying the number of tokens moved by the number of blocks in which they appeared.
    Spikes in burn rate could indicate large transactions or movement of tokens that have been held for a long time.

    Grouping by interval works by summing all burn rate records in the interval.
    """

    field :burn_rate, list_of(:burn_rate_data) do
      deprecate(~s/Use getMetric(metric: "age_destroyed") instead/)
      meta(access: :restricted)

      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&EtherbiResolver.token_age_consumed/3)
    end

    field :token_age_consumed, list_of(:token_age_consumed_data) do
      deprecate(~s/Use getMetric(metric: "age_destroyed") instead/)
      meta(access: :restricted)

      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&EtherbiResolver.token_age_consumed/3)
    end

    @desc ~s"""
    Fetch total amount of tokens for a project that were transacted on the blockchain, grouped by interval.
    Projects are referred to by a unique identifier (slug).

    This metric includes only on-chain volume, not volume in exchanges.

    Grouping by interval works by summing all transaction volume records in the interval.
    """
    field :transaction_volume, list_of(:transaction_volume) do
      deprecate(~s/Use getMetric(metric: "transaction_volume") instead/)
      meta(access: :restricted)

      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&EtherbiResolver.transaction_volume/3)
    end

    @desc ~s"""
    Fetch token age consumed in days for a project, grouped by interval.
    Projects are referred to by a unique identifier (slug). The token age consumed
    in days shows the average age of the tokens that were transacted for a given time period.

    This metric includes only on-chain transaction volume, not volume in exchanges.
    """
    field :average_token_age_consumed_in_days, list_of(:token_age) do
      meta(access: :restricted)

      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&EtherbiResolver.average_token_age_consumed_in_days/3)
    end

    @desc ~s"""
    Fetch token circulation for a project, grouped by interval.
    Projects are referred to by a unique identifier (slug).
    """
    field :token_circulation, list_of(:token_circulation) do
      deprecate(~s/Use getMetric(metric: "circulation_1d") instead/)
      meta(access: :restricted)

      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      @desc "The interval should represent whole days, i.e. `1d`, `48h`, `1w`, etc."
      arg(:interval, :interval, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&ClickhouseResolver.token_circulation/3)
    end

    @desc ~s"""
    Fetch token velocity for a project, grouped by interval.
    Projects are referred to by a unique identifier (slug).
    """
    field :token_velocity, list_of(:token_velocity) do
      deprecate(~s/Use getMetric(metric: "velocity") instead/)
      meta(access: :restricted)

      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      @desc "The interval should represent whole days, i.e. `1d`, `48h`, `1w`, etc."
      arg(:interval, :interval, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&ClickhouseResolver.token_velocity/3)
    end

    @desc ~s"""
    Fetch daily active addresses for a project within a given time period.
    Projects are referred to by a unique identifier (slug).

    This metric includes the number of unique addresses that participated in
    the transfers of given token during the day.

    Grouping by interval works by taking the mean of all daily active address
    records in the interval. The default value of the interval is 1 day, which yields
    the exact number of unique addresses for each day.
    """
    field :daily_active_addresses, list_of(:active_addresses) do
      deprecate(~s/Use getMetric(metric: "daily_active_addresses") instead/)
      meta(access: :free)

      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&ClickhouseResolver.daily_active_addresses/3)
    end

    @desc ~s"""
    Fetch the flow of funds into and out of an exchange wallet.
    This query returns the difference IN-OUT calculated for each interval.
    """
    field :exchange_funds_flow, list_of(:exchange_funds_flow) do
      deprecate(~s/Use getMetric(metric: "exchange_balance") instead/)
      meta(access: :restricted)

      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&EtherbiResolver.exchange_funds_flow/3)
    end

    @desc "Network growth returns the newly created addresses for a project in a given timeframe"
    field :network_growth, list_of(:network_growth) do
      deprecate(~s/Use getMetric(metric: "network_growth") instead/)
      meta(access: :restricted)

      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, non_null(:interval), default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&ClickhouseResolver.network_growth/3)
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

    # ADVANCED PLAN

    @desc "Returns Realized value - sum of the acquisition costs of an asset located in a wallet.
    The realized value across the whole network is computed by summing the realized values
    of all wallets holding tokens at the moment."
    field :realized_value, list_of(:realized_value) do
      deprecate(~s/Use getMetric(metric: "realized_value_usd") instead/)
      meta(access: :restricted)

      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&ClickhouseResolver.realized_value/3)
    end

    @desc "Returns MVRV(Market-Value-to-Realized-Value)"
    field :mvrv_ratio, list_of(:mvrv_ratio) do
      deprecate(~s/Use getMetric(metric: "mvrv_usd") instead/)
      meta(access: :restricted)

      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, non_null(:interval), default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&ClickhouseResolver.mvrv_ratio/3)
    end

    @desc """
    Returns NVT (Network-Value-to-Transactions-Ratio
    Daily Market Cap / Daily Transaction Volume
    Since Daily Transaction Volume gets rather noisy and easy to manipulate
    by transferring the same tokens through а couple of addresses repeatedly,
    it’s not an ideal measure of a network’s economic activity.
    That’s why we also offer another way to calculate NVT by using Daily Token Circulation.
    This method filters out excess transactions and provides a cleaner overview of
    a blockchain’s daily transaction throughput.
    """
    field :nvt_ratio, list_of(:nvt_ratio) do
      deprecate(
        ~s/Use getMetric(metric: "nvt") and getMetric(metric: "nvt_transaction_volume") instead/
      )

      meta(access: :restricted)

      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&ClickhouseResolver.nvt_ratio/3)
    end

    @desc ~s"""
    Fetch daily active deposits for a project within a given time period.
    Projects are referred to by a unique identifier (slug).
    """
    field :daily_active_deposits, list_of(:active_deposits) do
      meta(access: :restricted)

      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&ClickhouseResolver.daily_active_deposits/3)
    end

    @desc "List all exchanges"
    field :all_exchanges, list_of(:string) do
      meta(access: :free)

      arg(:slug, non_null(:string))
      arg(:is_dex, :boolean)

      cache_resolve(&ExchangeResolver.all_exchanges/3)
    end

    @desc """
    Returns distribution of miners between mining pools.
    What part of the miners are using top3, top10 and all the other pools.
    Currently only ETH is supported.
    """
    field :mining_pools_distribution, list_of(:mining_pools_distribution) do
      meta(access: :restricted)

      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&ClickhouseResolver.mining_pools_distribution/3)
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

    # TODO: Remove this. It is brought only temporary
    field :exchange_wallets, list_of(:wallet) do
      meta(access: :free)
      arg(:slug, non_null(:string))
      arg(:limit, :integer, default_value: 1000)

      middleware(BasicAuth)
      cache_resolve(&EtherbiResolver.exchange_wallets/3)
    end
  end
end
