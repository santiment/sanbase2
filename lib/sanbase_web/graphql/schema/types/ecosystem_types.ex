defmodule SanbaseWeb.Graphql.EcosystemTypes do
  use Absinthe.Schema.Notation

  object :ecosystem do
    field(:name, non_null(:string))
    field(:projects, list_of(:project))
  end
end
