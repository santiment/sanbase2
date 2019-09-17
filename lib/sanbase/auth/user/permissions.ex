defmodule Sanbase.Auth.User.Permissions do
  alias Sanbase.Auth.User
  alias Sanbase.Billing.{Subscription, Product}

  def permissions(%User{} = user) do
    user_subscriptions_product_ids = Subscription.user_subscriptions_product_ids(user)

    %{
      api: Product.product_api() in user_subscriptions_product_ids,
      sanbase: Product.product_sanbase() in user_subscriptions_product_ids,
      spreadsheet: Product.product_sanbase() in user_subscriptions_product_ids,
      sangraphs: Product.product_sangraphs() in user_subscriptions_product_ids
    }
  end

  def no_permissions() do
    %{
      api: false,
      sanbase: false,
      spreadsheet: false,
      sangraphs: false
    }
  end

  def full_permissions() do
    %{
      api: true,
      sanbase: true,
      spreadsheet: true,
      sangraphs: true
    }
  end
end
