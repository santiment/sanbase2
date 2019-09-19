defmodule Sanbase.ExAdmin.Billing.PromoCoupon do
  use ExAdmin.Register

  register_resource Sanbase.Billing.Subscription.PromoCoupon do
    action_items(only: [:show])

    show _promo_coupon do
      attributes_table(all: true)
    end
  end
end
