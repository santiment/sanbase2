defmodule SanbaseWeb.Graphql.HyperliquidTypes do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.HyperliquidBboResolver
  alias SanbaseWeb.Graphql.Complexity
  alias SanbaseWeb.Graphql.Middlewares.AccessControl

  @desc ~s"""
  A bucketed BBO (best bid / best offer) snapshot for a Hyperliquid asset.

  Within each interval bucket we return the values from the row with the
  largest `dt` (atomic snapshot — bid and ask always come from the same row).

  `mid_price` and `weighted_mid_price` are null whenever either side of the
  book is missing.
  """
  object :hyperliquid_bbo_point do
    field(:datetime, non_null(:datetime))
    field(:bid_price, :float)
    field(:bid_volume, :float)
    field(:ask_price, :float)
    field(:ask_volume, :float)

    @desc "Arithmetic mid: (bid_price + ask_price) / 2."
    field(:mid_price, :float)

    @desc ~s"""
    Volume-weighted mid:
    (bid_price * ask_volume + ask_price * bid_volume) / (bid_volume + ask_volume).
    """
    field(:weighted_mid_price, :float)
  end

  @desc ~s"""
  Entry point for Hyperliquid BBO (best bid / best offer) data.

  Use `timeseriesData` to fetch a bucketed BBO timeseries for a given slug,
  and `availableProjects` / `availableNonCryptoAssets` to list the crypto
  projects and non-crypto assets backed by a Hyperliquid source mapping.
  """
  object :hyperliquid_bbo_data do
    @desc ~s"""
    Fetch Hyperliquid BBO timeseries for a given slug.

    Each output row represents one interval bucket; within a bucket, bid and
    ask values are taken from the row with the largest `dt`, so every row
    reflects a single source snapshot.
    """
    field :timeseries_data, list_of(:hyperliquid_bbo_point) do
      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, non_null(:interval))
      arg(:caching_params, :caching_params_input_object)

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&HyperliquidBboResolver.timeseries_data/3, ttl: 60, max_ttl_offset: 30)
    end

    @desc ~s"""
    List of projects that have a `hyperliquid` source slug mapping and can be
    queried via `timeseriesData`.
    """
    field :available_projects, list_of(:project) do
      cache_resolve(&HyperliquidBboResolver.available_projects/3, ttl: 300)
    end

    @desc ~s"""
    List of non-crypto assets (gold, SPX, …) that have a `hyperliquid` source
    slug mapping and can be queried via `timeseriesData`.
    """
    field :available_non_crypto_assets, list_of(:non_crypto_asset) do
      cache_resolve(&HyperliquidBboResolver.available_non_crypto_assets/3, ttl: 300)
    end
  end
end
