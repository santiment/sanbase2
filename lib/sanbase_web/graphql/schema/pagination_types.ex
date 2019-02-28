defmodule SanbaseWeb.Graphql.PaginationTypes do
  use Absinthe.Schema.Notation

  object :cursor do
    field(:before, :naive_datetime)
    field(:after, :naive_datetime)
  end
end
