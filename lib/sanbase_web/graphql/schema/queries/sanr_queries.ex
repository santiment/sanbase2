defmodule SanbaseWeb.Graphql.Schema.SanrQueries do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.SanrResolver

  object :sanr_mutations do
    @desc """
    Add emails from sanr.netweork landing page
    """
    field :add_sanr_email, :boolean do
      arg(:email, non_null(:string))

      resolve(&SanrResolver.add_sanr_email/3)
    end
  end
end
