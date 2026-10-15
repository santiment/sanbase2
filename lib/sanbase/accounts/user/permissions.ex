defmodule Sanbase.Accounts.User.Permissions do
  alias Sanbase.Accounts.User
  alias Sanbase.Billing.{Subscription, Product}

  def get_roles(%User{roles: roles}) do
    Enum.filter(roles, fn role ->
      role in ["registry_viewer", "registry_editor", "registry_owner"]
    end)
  end

  def permissions(%User{} = user) do
    Subscription.user_subscriptions_product_ids(user)
    |> permissions_from_product_ids()
  end

  @doc """
  Same as `permissions/1`, computed from the user's already fetched active
  subscriptions (with `plan` preloaded) instead of querying them again.
  """
  def permissions_from_subscriptions(subscriptions) when is_list(subscriptions) do
    subscriptions
    |> Enum.map(& &1.plan.product_id)
    |> permissions_from_product_ids()
  end

  defp permissions_from_product_ids(product_ids) do
    # Sanbase or API plan subscription gives access to all products
    has_access =
      Product.product_api() in product_ids ||
        Product.product_sanbase() in product_ids

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
