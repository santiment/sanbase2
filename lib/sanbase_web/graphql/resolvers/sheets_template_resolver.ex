defmodule SanbaseWeb.Graphql.Resolvers.SheetsTemplateResolver do
  alias Sanbase.SheetsTemplate
  alias Sanbase.Billing

  def get_sheets_templates(_root, _args, %{context: %{auth: %{current_user: user}}}) do
    plan = Billing.sanbase_plan_name(user)

    {:ok, SheetsTemplate.get_all(%{is_logged_in: true, plan_name: plan})}
  end

  def get_sheets_templates(_root, _args, _resolution) do
    {:ok, SheetsTemplate.get_all(%{is_logged_in: false})}
  end
end
