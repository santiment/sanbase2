defmodule SanbaseWeb.Graphql.Schema do
  @moduledoc ~s"""
  The definition of the GraphQL Schema.

  There are no fields explicitlty defined here. Queries, mutations and types
  are defined in modules separated by concern. Then they are imported
  via import_types/1 or import_fields/1

  When defining a query there must be defined also a meta key 'subscription'.
  These subscriptions have the following values:
    > free
    > basic
    > pro
    > premium
    > enterprise
  """
  use Absinthe.Schema
  use Absinthe.Ecto, repo: Sanbase.Repo

  alias SanbaseWeb.Graphql
  alias SanbaseWeb.Graphql.Prometheus
  alias SanbaseWeb.Graphql.{SanbaseRepo, SanbaseDataloader}
  alias SanbaseWeb.Graphql.Middlewares.ApiUsage

  import_types(Graphql.CustomTypes.Decimal)
  import_types(Graphql.CustomTypes.DateTime)
  import_types(Graphql.CustomTypes.JSON)
  import_types(Graphql.CustomTypes.Interval)
  import_types(Absinthe.Plug.Types)
  import_types(Graphql.TagTypes)
  import_types(Graphql.AccountTypes)
  import_types(Graphql.TransactionTypes)
  import_types(Graphql.FileTypes)
  import_types(Graphql.UserListTypes)
  import_types(Graphql.MarketSegmentTypes)
  import_types(Graphql.UserSettingsTypes)
  import_types(Graphql.UserTriggerTypes)
  import_types(Graphql.PaginationTypes)
  import_types(Graphql.SignalsHistoricalActivityTypes)
  import_types(Graphql.TimelineEventTypes)
  import_types(Graphql.InsightTypes)
  import_types(Graphql.TwitterTypes)
  import_types(Graphql.MetricTypes)

  import_types(Graphql.Schema.MetricQueries)
  import_types(Graphql.Schema.SocialDataQueries)
  import_types(Graphql.Schema.WatchlistQueries)
  import_types(Graphql.Schema.ProjectQueries)
  import_types(Graphql.Schema.InsightQueries)
  import_types(Graphql.Schema.TechIndicatorsQueries)
  import_types(Graphql.Schema.PriceQueries)
  import_types(Graphql.Schema.GithubQueries)
  import_types(Graphql.Schema.BlockchainQueries)
  import_types(Graphql.Schema.SignalQueries)
  import_types(Graphql.Schema.FeaturedQueries)
  import_types(Graphql.Schema.UserQueries)
  import_types(Graphql.Schema.TimelineQueries)
  import_types(Graphql.Schema.BillingQueries)

  def dataloader() do
    Dataloader.new(timeout: :timer.seconds(20))
    |> Dataloader.add_source(SanbaseRepo, SanbaseRepo.data())
    |> Dataloader.add_source(SanbaseDataloader, SanbaseDataloader.data())
  end

  def context(ctx) do
    ctx
    |> Map.put(:loader, dataloader())
  end

  def plugins do
    [
      Absinthe.Middleware.Dataloader | Absinthe.Plugin.defaults()
    ]
  end

  def middleware(middlewares, field, object) do
    case object.identifier do
      :query ->
        [
          ApiUsage
          | middlewares
            |> Prometheus.HistogramInstrumenter.instrument(field, object)
            |> Prometheus.CounterInstrumenter.instrument(field, object)
        ]

      _ ->
        middlewares
        |> Prometheus.HistogramInstrumenter.instrument(field, object)
        |> Prometheus.CounterInstrumenter.instrument(field, object)
    end
  end

  query do
    import_fields(:metric_queries)
    import_fields(:social_data_queries)
    import_fields(:user_list_queries)
    import_fields(:project_queries)
    import_fields(:project_eth_spent_queries)
    import_fields(:insight_queries)
    import_fields(:tech_indicators_queries)
    import_fields(:price_queries)
    import_fields(:github_queries)
    import_fields(:blockchain_queries)
    import_fields(:signal_queries)
    import_fields(:featured_queries)
    import_fields(:user_queries)
    import_fields(:timeline_queries)
    import_fields(:billing_queries)
  end

  mutation do
    import_fields(:user_list_mutations)
    import_fields(:insight_mutations)
    import_fields(:signal_mutations)
    import_fields(:user_mutations)
    import_fields(:billing_mutations)
  end

  enum(:side_enum, values: [:buy, :sell])

  object :exchange_market_depth do
    field(:source, :string)
    field(:symbol, :string)
    field(:timestamp, :datetime)
    field(:ask, :float)
    field(:asks025_percent_depth, :float)
    field(:asks025_percent_volume, :float)
    field(:asks05_percent_depth, :float)
    field(:asks05_percent_volume, :float)
    field(:asks075_percent_depth, :float)
    field(:asks075_percent_volume, :float)
    field(:asks10_percent_depth, :float)
    field(:asks10_percent_volume, :float)
    field(:asks1_percent_depth, :float)
    field(:asks1_percent_volume, :float)
    field(:asks20_percent_depth, :float)
    field(:asks20_percent_volume, :float)
    field(:asks2_percent_depth, :float)
    field(:asks2_percent_volume, :float)
    field(:asks30_percent_depth, :float)
    field(:asks30_percent_volume, :float)
    field(:asks5_percent_depth, :float)
    field(:asks5_percent_volume, :float)
    field(:bid, :float)
    field(:bids025_percent_depth, :float)
    field(:bids025_percent_volume, :float)
    field(:bids05_percent_depth, :float)
    field(:bids05_percent_volume, :float)
    field(:bids075_percent_depth, :float)
    field(:bids075_percent_volume, :float)
    field(:bids10_percent_depth, :float)
    field(:bids10_percent_volume, :float)
    field(:bids1_percent_depth, :float)
    field(:bids1_percent_volume, :float)
    field(:bids20_percent_depth, :float)
    field(:bids20_percent_volume, :float)
    field(:bids2_percent_depth, :float)
    field(:bids2_percent_volume, :float)
    field(:bids30_percent_depth, :float)
    field(:bids30_percent_volume, :float)
    field(:bids5_percent_depth, :float)
    field(:bids5_percent_volume, :float)
  end

  object :exchange_trade do
    field(:source, :string)
    field(:symbol, :string)
    field(:timestamp, :datetime)
    field(:side, :side_enum)
    field(:amount, :float)
    field(:price, :float)
    field(:cost, :float)
  end

  subscription do
    field :exchange_market_depth, :exchange_market_depth do
      arg(:source, non_null(:string))
      arg(:symbol, :string)

      config(fn
        %{source: source, symbol: symbol}, _ when not is_nil(symbol) ->
          {:ok, topic: source <> symbol}

        %{source: source}, _ ->
          {:ok, topic: source}
      end)
    end

    field :exchange_trades, :exchange_trade do
      arg(:source, :string)
      arg(:symbol, :string)

      config(fn
        %{source: source, symbol: symbol}, _ when not is_nil(symbol) ->
          {:ok, topic: source <> symbol}

        %{source: source}, _ when not is_nil(source) ->
          {:ok, topic: source}

        _, _ ->
          {:ok, topic: "*"}
      end)
    end
  end
end
