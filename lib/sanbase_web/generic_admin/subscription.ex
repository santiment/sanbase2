defmodule SanbaseWeb.GenericAdmin.Subscription do
  @behaviour SanbaseWeb.GenericAdmin
  def schema_module, do: Sanbase.Billing.Subscription
  def resource_name, do: "subscriptions"
  def singular_resource_name, do: "subscription"

  def resource do
    %{
      preloads: [:user, plan: [:product]],
      actions: [:edit],
      fields_override: %{
        user_id: %{
          value_modifier: &__MODULE__.user_func/1
        },
        plan_id: %{
          value_modifier: &__MODULE__.plan_func/1
        }
      }
    }
  end

  def has_many(_subscription) do
    []
  end

  def belongs_to(_subscription) do
    []
  end

  def plan_func(row) do
    link_content = "#{row.plan.product.name}/#{row.plan.name}"
    SanbaseWeb.GenericAdmin.resource_link("plans", row.plan_id, link_content)
  end

  def user_func(row) do
    link_content = row.user.email || row.user.username || row.user.id
    SanbaseWeb.GenericAdmin.resource_link("users", row.user_id, link_content)
  end
end
