defmodule SanbaseWeb.Graphql.Schema.ShortUrlQueries do
  @moduledoc ~s"""
  Queries and mutations for working with short urls
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.ShortUrlResolver

  object :short_url_queries do
    @desc "Get the full url that corresponds to the full url."
    field :get_full_url, :string do
      meta(access: :free)
      arg(:short_url, non_null(:string))

      resolve(&ShortUrlResolver.get_full_url/3)
    end
  end

  object :short_url_mutations do
    @desc "Create a short url that will resolve to the full url."
    field :create_short_url, :string do
      arg(:full_url, non_null(:string))

      resolve(&ShortUrlResolver.create_short_url/3)
    end
  end
end
