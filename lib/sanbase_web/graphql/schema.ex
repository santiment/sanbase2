defmodule SanbaseWeb.Graphql.Schema do
  use Absinthe.Schema
  use Absinthe.Ecto, repo: Sanbase.Repo

  alias SanbaseWeb.Graphql
  alias SanbaseWeb.Graphql.{SanbaseRepo, SanbaseDataloader}
  alias SanbaseWeb.Graphql.Middlewares.ApiUsage

  import_types(Absinthe.Plug.Types)
  import_types(Absinthe.Type.Custom)
  import_types(Graphql.TagTypes)
  import_types(Graphql.CustomTypes)
  import_types(Graphql.AccountTypes)
  import_types(Graphql.TransactionTypes)
  import_types(Graphql.FileTypes)
  import_types(Graphql.UserListTypes)
  import_types(Graphql.MarketSegmentTypes)
  import_types(Graphql.UserSettingsTypes)
  import_types(Graphql.UserTriggerTypes)
  import_types(Graphql.CustomTypes.JSON)
  import_types(Graphql.PaginationTypes)
  import_types(Graphql.SignalsHistoricalActivityTypes)
  import_types(Graphql.TimelineEventTypes)
  import_types(Graphql.InsightTypes)
  import_types(Graphql.TwitterTypes)

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
  import_types(Graphql.Schema.PricingQueries)

  def dataloader() do
    # 11 seconds is 1s more than the influxdb timeout
    Dataloader.new(timeout: :timer.seconds(11))
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
    prometeheus_middlewares =
      Graphql.Prometheus.HistogramInstrumenter.instrument(middlewares, field, object)
      |> Graphql.Prometheus.CounterInstrumenter.instrument(field, object)

    case object.identifier do
      :query ->
        [ApiUsage | prometeheus_middlewares]

      _ ->
        prometeheus_middlewares
    end
  end

  query do
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
    import_fields(:pricing_queries)
  end

  mutation do
    import_fields(:user_list_mutations)
    import_fields(:insight_mutations)
    import_fields(:signal_mutations)
    import_fields(:user_mutations)
    import_fields(:pricing_mutations)
  end
end
