defmodule SanbaseWeb.GenericAdmin.Subscription do
  alias Sanbase.Billing.Subscription
  alias SanbaseWeb.GenericAdmin.SubscriptionHelper

  @resource %{
    "subscriptions" => %{
      module: Subscription,
      admin_module: __MODULE__,
      singular: "subscription",
      preloads: [:user, plan: [:product]],
      index_fields: [:id, :plan, :status],
      edit_fields: [],
      show_fields: :all,
      actions: [:show, :edit],
      funcs: %{
        plan: &SubscriptionHelper.plan_func/1
      }
    }
  }

  def resource, do: @resource

  def has_many(_subscription) do
    []
  end

  def belongs_to(_subscription) do
    []
  end
end

defmodule SanbaseWeb.GenericAdmin.SubscriptionHelper do
  def plan_func(row) do
    IO.inspect(row)
    "#{row.plan.product.name}/#{row.plan.name}"
  end
end
