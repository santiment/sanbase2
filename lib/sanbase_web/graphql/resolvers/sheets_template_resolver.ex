defmodule SanbaseWeb.Graphql.Resolvers.SheetsTemplateResolver do
  @moduledoc false
  alias Sanbase.Billing.Product
  alias Sanbase.Billing.Subscription
  alias Sanbase.SheetsTemplate

  require Logger

  def get_sheets_templates(_root, _args, %{context: %{auth: %{current_user: user}}}) do
    plan =
      user
      |> Subscription.current_subscription(Product.product_sanbase())
      |> Subscription.plan_name()

    {:ok, SheetsTemplate.get_all(%{is_logged_in: true, plan_name: plan})}
  end

  def get_sheets_templates(_root, _args, _resolution) do
    {:ok, SheetsTemplate.get_all(%{is_logged_in: false})}
  end
end
