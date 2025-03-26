defmodule SanbaseWeb.Graphql.ShortUrlTypes do
  use Absinthe.Schema.Notation

  object :short_url do
    field(:id, :integer)
    field(:short_url, :string)
    field(:full_url, :string)
    field(:data, :string)
  end
end
