defmodule SanbaseWeb.GenericAdmin.Subscription do
  alias Sanbase.Billing.Subscription
  alias SanbaseWeb.GenericAdmin.SubscriptionHelper

  @resource %{
    "subscriptions" => %{
      module: Subscription,
      admin_module: __MODULE__,
      singular: "subscription",
      preloads: [:user, plan: [:product]],
      edit_fields: [],
      show_fields: :all,
      actions: [:show, :edit],
      funcs: %{
        plan_id: &SubscriptionHelper.plan_func/1,
        user_id: &SubscriptionHelper.user_func/1
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
    link_content = "#{row.plan.product.name}/#{row.plan.name}"
    href("plans", row.plan_id, link_content)
  end

  def user_func(row) do
    link_content = row.user.email || row.user.username || row.user.id
    href("users", row.user_id, link_content)
  end

  def href(resource, id, label) do
    relative_url =
      SanbaseWeb.Router.Helpers.generic_path(SanbaseWeb.Endpoint, :show, id, resource: resource)

    Phoenix.HTML.Link.link(label, to: relative_url, class: "text-blue-600 hover:text-blue-800")
  end
end
