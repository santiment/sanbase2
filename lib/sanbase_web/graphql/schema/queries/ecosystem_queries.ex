defmodule SanbaseWeb.Graphql.Schema.EcosystemQueries do
  @moduledoc ~s"""
  Queries and mutations for working with Insights
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.EcosystemResolver

  object :ecosystem_queries do
    @desc """
    Get the list of available ecosystems along with some data for them
    """
    field :get_ecosystems, list_of(:ecosystem) do
      meta(access: :free)

      arg(:ecosystems, list_of(:string))
      resolve(&EcosystemResolver.get_ecosystems/3)
    end
  end
end
