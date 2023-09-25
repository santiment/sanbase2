defmodule SanbaseWeb.Graphql.Schema.FreeFormJsonStorageQueries do
  @moduledoc ~s"""
  Queries and mutations for working with free form JSON storage
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.FreeFormJsonStorageResolver
  alias SanbaseWeb.Graphql.Middlewares.UserAuth

  object :free_form_json_storage_queries do
    field :get_free_form_json, :free_form_json_storage do
      meta(access: :free)

      arg(:key, non_null(:string))

      resolve(&FreeFormJsonStorageResolver.get_json/3)
    end
  end

  object :free_form_json_storage_mutations do
    field :create_free_form_json, :free_form_json_storage do
      meta(access: :free)

      arg(:key, non_null(:string))
      arg(:value, non_null(:json))

      middleware(UserAuth, access_by_email_pattern: ~r/@santiment.net$/)

      resolve(&FreeFormJsonStorageResolver.create_json/3)
    end

    field :update_free_form_json, :free_form_json_storage do
      meta(access: :free)

      arg(:key, non_null(:string))
      arg(:value, non_null(:json))

      middleware(UserAuth, access_by_email_pattern: ~r/@santiment.net$/)

      resolve(&FreeFormJsonStorageResolver.update_json/3)
    end

    field :delete_free_form_json, :free_form_json_storage do
      meta(access: :free)

      arg(:key, non_null(:string))

      middleware(UserAuth, access_by_email_pattern: ~r/@santiment.net$/)

      resolve(&FreeFormJsonStorageResolver.delete_json/3)
    end
  end
end
