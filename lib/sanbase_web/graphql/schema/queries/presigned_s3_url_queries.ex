defmodule SanbaseWeb.Graphql.Schema.PresignedS3UrlQueries do
  @moduledoc ~s"""
  Queries and mutations for working with short urls
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Middlewares.UserAuth
  alias SanbaseWeb.Graphql.Resolvers.PresignedS3UrlResolver

  object :presigned_s3_url_queries do
    @desc "Get the full url that corresponds to the full url."
    field :get_presigned_s3_url, :string do
      meta(access: :free)
      arg(:object, non_null(:string))

      middleware(UserAuth)

      resolve(&PresignedS3UrlResolver.get_presigned_s3_url/3)
    end
  end
end
