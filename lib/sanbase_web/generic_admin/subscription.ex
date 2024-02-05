defmodule SanbaseWeb.GenericAdmin.Subscription do
  def schema_module, do: Sanbase.Billing.Subscription

  def resource do
    %{
      preloads: [:user, plan: [:product]],
      actions: [:show, :edit],
      funcs: %{
        plan_id: &__MODULE__.plan_func/1,
        user_id: &__MODULE__.user_func/1
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
