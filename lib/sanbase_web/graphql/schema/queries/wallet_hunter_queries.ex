defmodule SanbaseWeb.Graphql.Schema.WalletHunterQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.WalletHunterResolver

  enum :sort_direction do
    value(:asc)
    value(:desc)
  end

  input_object :wallet_hunters_filter_object do
    field(:field, :string)
    field(:value, :string)
  end

  input_object :wallet_hunters_sort_object do
    field(:field, :string)
    field(:direction, :sort_direction)
  end

  input_object :wallet_hunters_proposals_selector_input_object do
    field(:filter, list_of(:wallet_hunters_filter_object))
    field(:sort_by, :wallet_hunters_sort_object)
    field(:page, :integer, default_value: 1)
    field(:page_size, :integer, default_value: 10)
  end

  object :wallet_hunter_queries do
    field :all_wallet_hunter_proposals, list_of(:wallet_hunter_proposal) do
      meta(access: :free)
      arg(:selector, :wallet_hunters_proposals_selector_input_object)

      cache_resolve(&WalletHunterResolver.all_wallet_hunter_proposals/3)
    end
  end
end
