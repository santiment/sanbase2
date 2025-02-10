defmodule SanbaseWeb.Graphql.Schema.PromoterQueries do
  @moduledoc false
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Middlewares.JWTAuth
  alias SanbaseWeb.Graphql.Resolvers.PromoterResolver

  object :promoter_queries do
    @desc ~s"""
    Show promoter details and stats
    """
    field :show_promoter, :promoter do
      meta(access: :free)

      middleware(JWTAuth)

      resolve(&PromoterResolver.show_promoter/3)
    end
  end

  object :promoter_mutations do
    @desc ~s"""
    Create new promoter.
    Arguments:
      * `ref_id` - promoter chosen referral id. Will be shown in referral link: `"https://app.santiment.net/pricing?fpr=<ref_id>"`
      If not provided the system will generate one.
      * `promo_code` - 	unique promo code from Stripe to assign to this promoter for coupon tracking.
      Sales tracking can be done only with promo_code without referral link.
    """
    field :create_promoter, :promoter do
      arg(:ref_id, :string)
      arg(:promo_code, :string)

      middleware(JWTAuth)

      resolve(&PromoterResolver.create_promoter/3)
    end
  end
end
