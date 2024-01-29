defmodule SanbaseWeb.Graphql.Schema.UserAffiliateDetailsQueries do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Middlewares.UserAuth
  alias SanbaseWeb.Graphql.Resolvers.UserAffiliateDetailsResolver

  object :user_affiliate_details_mutations do
    field :add_user_affiliate_details, :boolean do
      meta(access: :free)

      arg(:telegram_handle, non_null(:string))
      arg(:marketing_channels, :string)

      middleware(UserAuth)

      resolve(&UserAffiliateDetailsResolver.add_user_affiliate_details/3)
    end
  end
end
