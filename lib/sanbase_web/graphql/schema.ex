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
    > custom
  """
  use Absinthe.Schema

  alias SanbaseWeb.Graphql
  alias SanbaseWeb.Graphql.Prometheus
  alias SanbaseWeb.Graphql.{SanbaseRepo, SanbaseDataloader}
  alias SanbaseWeb.Graphql.Middlewares.ApiUsage

  # Types
  import_types(Absinthe.Plug.Types)
  import_types(Graphql.AggregationTypes)
  import_types(Graphql.BlockchainAddressType)
  import_types(Graphql.CommentTypes)
  import_types(Graphql.CustomTypes.Date)
  import_types(Graphql.CustomTypes.DateTime)
  import_types(Graphql.CustomTypes.Decimal)
  import_types(Graphql.CustomTypes.Interval)
  import_types(Graphql.CustomTypes.IntervalOrNow)
  import_types(Graphql.CustomTypes.JSON)
  # End of custom types
  import_types(Graphql.AggregationTypes)
  import_types(Graphql.AlertsHistoricalActivityTypes)
  import_types(Graphql.Schema.BillingTypes)
  import_types(Graphql.BlockchainAddressType)
  import_types(Graphql.ClickhouseTypes)
  import_types(Graphql.CommentTypes)
  import_types(Graphql.EtherbiTypes)
  import_types(Graphql.ExchangeTypes)
  import_types(Graphql.FileTypes)
  import_types(Graphql.GithubTypes)
  import_types(Graphql.HistoricalBalanceTypes)
  import_types(Graphql.InsightTypes)
  import_types(Graphql.MarketSegmentTypes)
  import_types(Graphql.MetricTypes)
  import_types(Graphql.PaginationTypes)
  import_types(Graphql.PriceTypes)
  import_types(Graphql.ProjectChartTypes)
  import_types(Graphql.ProjectTypes)
  import_types(Graphql.ReportTypes)
  import_types(Graphql.ResearchTypes)
  import_types(Graphql.Schema.PromoterTypes)
  import_types(Graphql.ShortUrlTypes)
  import_types(Graphql.SocialDataTypes)
  import_types(Graphql.TableConfigurationTypes)
  import_types(Graphql.TagTypes)
  import_types(Graphql.TechIndicatorsTypes)
  import_types(Graphql.TimelineEventTypes)
  import_types(Graphql.TransactionTypes)
  import_types(Graphql.TwitterTypes)
  import_types(Graphql.UserListTypes)
  import_types(Graphql.UserSettingsTypes)
  import_types(Graphql.UserTriggerTypes)
  import_types(Graphql.UserTypes)
  import_types(Graphql.SignalTypes)
  import_types(Graphql.WidgetTypes)

  # Queries and mutations
  import_types(Graphql.Schema.SignalQueries)
  import_types(Graphql.Schema.BillingQueries)
  import_types(Graphql.Schema.BlockchainAddressQueries)
  import_types(Graphql.Schema.BlockchainMetricQueries)
  import_types(Graphql.Schema.ChartConfigurationQueries)
  import_types(Graphql.Schema.CommentQueries)
  import_types(Graphql.Schema.EmailQueries)
  import_types(Graphql.Schema.ExchangeQueries)
  import_types(Graphql.Schema.FeaturedQueries)
  import_types(Graphql.Schema.GithubQueries)
  import_types(Graphql.Schema.HistoricalBalanceQueries)
  import_types(Graphql.Schema.InsightQueries)
  import_types(Graphql.Schema.IntercomQueries)
  import_types(Graphql.Schema.IntercomQueries)
  import_types(Graphql.Schema.MetricQueries)
  import_types(Graphql.Schema.PriceQueries)
  import_types(Graphql.Schema.ProjectQueries)
  import_types(Graphql.Schema.PromoterQueries)
  import_types(Graphql.Schema.ReportQueries)
  import_types(Graphql.Schema.ResearchQueries)
  import_types(Graphql.Schema.ShortUrlQueries)
  import_types(Graphql.Schema.SocialDataQueries)
  import_types(Graphql.Schema.TableConfigurationQueries)
  import_types(Graphql.Schema.TechIndicatorsQueries)
  import_types(Graphql.Schema.TimelineQueries)
  import_types(Graphql.Schema.UserQueries)
  import_types(Graphql.Schema.UserTriggerQueries)
  import_types(Graphql.Schema.UserListQueries)
  import_types(Graphql.Schema.WidgetQueries)

  def dataloader() do
    Dataloader.new(timeout: :timer.seconds(20), get_policy: :return_nil_on_error)
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
    import_fields(:signal_queries)
    import_fields(:billing_queries)
    import_fields(:blockchain_address_queries)
    import_fields(:blockchain_metric_queries)
    import_fields(:comment_queries)
    import_fields(:exchange_queries)
    import_fields(:featured_queries)
    import_fields(:github_queries)
    import_fields(:historical_balance_queries)
    import_fields(:insight_queries)
    import_fields(:intercom_queries)
    import_fields(:intercom_queries)
    import_fields(:metric_queries)
    import_fields(:price_queries)
    import_fields(:project_chart_queries)
    import_fields(:project_eth_spent_queries)
    import_fields(:project_queries)
    import_fields(:promoter_queries)
    import_fields(:report_queries)
    import_fields(:research_queries)
    import_fields(:short_url_queries)
    import_fields(:alert_queries)
    import_fields(:social_data_queries)
    import_fields(:table_configuration_queries)
    import_fields(:tech_indicators_queries)
    import_fields(:timeline_queries)
    import_fields(:user_list_queries)
    import_fields(:user_queries)
    import_fields(:widget_queries)
  end

  mutation do
    import_fields(:billing_mutations)
    import_fields(:comment_mutations)
    import_fields(:email_mutations)
    import_fields(:insight_mutations)
    import_fields(:intercom_mutations)
    import_fields(:project_chart_mutations)
    import_fields(:promoter_mutations)
    import_fields(:report_mutations)
    import_fields(:short_url_mutations)
    import_fields(:alert_mutations)
    import_fields(:table_configuration_mutations)
    import_fields(:timeline_mutations)
    import_fields(:user_list_mutations)
    import_fields(:user_mutations)
  end
end
