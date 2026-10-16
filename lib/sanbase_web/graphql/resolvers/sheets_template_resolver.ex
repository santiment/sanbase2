defmodule SanbaseWeb.Graphql.Resolvers.SheetsTemplateResolver do
  alias Sanbase.SheetsTemplate
  alias Sanbase.Billing.{Subscription, Product}

  def get_sheets_templates(_root, _args, %{context: %{auth: %{current_user: _} = auth}}) do
    plan =
      Subscription.current_subscription_from_auth(auth, Product.product_sanbase())
      |> Subscription.plan_name()

    {:ok, SheetsTemplate.get_all(%{is_logged_in: true, plan_name: plan})}
  end

  def get_sheets_templates(_root, _args, _resolution) do
    {:ok, SheetsTemplate.get_all(%{is_logged_in: false})}
  end
end
