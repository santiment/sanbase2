defmodule SanbaseWeb.Graphql.Schema.WebinarQueries do
  @moduledoc false
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Middlewares.JWTAuth
  alias SanbaseWeb.Graphql.Resolvers.WebinarResolver

  object :webinar_queries do
    @desc ~s"""
    List all webinars.
    """
    field :get_webinars, list_of(:webinar) do
      meta(access: :free)

      resolve(&WebinarResolver.get_webinars/3)
    end
  end

  object :webinar_mutations do
    @desc ~s"""
    Register for webinar
    """
    field :register_for_webinar, :boolean do
      meta(access: :free)
      middleware(JWTAuth)
      arg(:webinar_id, :id)

      resolve(&WebinarResolver.register_for_webinar/3)
    end
  end
end
