defmodule Sanbase.Accounts.User.Permissions do
  alias Sanbase.Accounts.User
  alias Sanbase.Billing.{Subscription, Product}

  def get_roles(%User{roles: roles}) do
    Enum.filter(roles, fn role ->
      role in ["registry_viewer", "registry_editor", "registry_owner"]
    end)
  end

  def permissions(%User{} = user) do
    user_subscriptions_product_ids = Subscription.user_subscriptions_product_ids(user)

    # Sanbase or API plan subscription gives access to all products
    has_access =
      Product.product_api() in user_subscriptions_product_ids ||
        Product.product_sanbase() in user_subscriptions_product_ids

    %{
      api: has_access,
      sanbase: has_access,
      spreadsheet: has_access
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
