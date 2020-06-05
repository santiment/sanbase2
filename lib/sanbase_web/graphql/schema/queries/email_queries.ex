defmodule SanbaseWeb.Graphql.Schema.EmailQueries do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.EmailResolver

  object :email_mutations do
    field :subscribe_weekly, :boolean do
      arg(:email, non_null(:string))

      resolve(&EmailResolver.subscribe_weekly/3)
    end
  end
end
