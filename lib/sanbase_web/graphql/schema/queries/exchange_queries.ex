defmodule SanbaseWeb.Graphql.Schema.ExchangeQueries do
  @moduledoc false
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.Middlewares.AccessControl
  alias SanbaseWeb.Graphql.Resolvers.ExchangeResolver

  object :exchange_queries do
    field :top_exchanges_by_balance, list_of(:top_exchange_balance) do
      meta(access: :restricted)

      arg(:slug, :string)
      arg(:selector, :metric_target_selector_input_object)
      arg(:limit, :integer, default_value: 10)

      middleware(AccessControl)

      cache_resolve(&ExchangeResolver.top_exchanges_by_balance/3,
        ttl: 600,
        max_ttl_offset: 120
      )
    end
  end
end
