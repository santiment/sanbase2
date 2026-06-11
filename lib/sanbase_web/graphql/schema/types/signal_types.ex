defmodule SanbaseWeb.Graphql.SignalTypes do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.SignalResolver

  input_object :anomaly_target_selector_input_object do
    field(:slug, :string)
    field(:slugs, list_of(:string))
    field(:market_segments, list_of(:string))
    field(:ignored_slugs, list_of(:string))
    field(:watchlist_id, :integer)
    field(:watchlist_slug, :string)
  end

  object :anomaly do
    field(:anomaly, non_null(:string))
    field(:is_hidden, non_null(:boolean))
    field(:datetime, :datetime)
    field(:slug, :string)
    field(:value, :float)
    field(:metadata, :json)

    # The anomalies can be computed for assets that are no longer linked to
    # an existing project. In this case this field can be nil.
    field :project, :project do
      cache_resolve(&SignalResolver.project/3)
    end
  end
end
