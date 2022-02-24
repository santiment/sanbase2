defmodule SanbaseWeb.Graphql.ShortUrlTypes do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.ShortUrlResolver

  object :short_url do
    field(:id, :integer)
    field(:short_url, :string)
    field(:full_url, :string)
    field(:data, :string)

    field :comments_count, :integer do
      resolve(&ShortUrlResolver.comments_count/3)
    end
  end
end
