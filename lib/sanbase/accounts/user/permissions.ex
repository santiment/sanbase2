defmodule Sanbase.Accounts.User.Permissions do
  alias Sanbase.Accounts.User
  alias Sanbase.Billing.{Subscription, Product}

  def permissions(%User{} = user) do
    user_subscriptions_product_ids = Subscription.user_subscriptions_product_ids(user)

    %{
      api: Product.product_api() in user_subscriptions_product_ids,
      sanbase: Product.product_sanbase() in user_subscriptions_product_ids,
      spreadsheet: Product.product_sanbase() in user_subscriptions_product_ids
    }
  end

  def no_permissions() do
    %{
      api: false,
      sanbase: false,
      spreadsheet: false
    }
  end

  def full_permissions() do
    %{
      api: true,
      sanbase: true,
      spreadsheet: true
    }
  end
end
