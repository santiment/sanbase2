defmodule SanbaseWeb.Graphql.Resolvers.ReportResolver do
  alias Sanbase.Report
  alias Sanbase.Billing.{Subscription, Product}

  def upload_report(_root, %{report: report} = args, _resolution) do
    {params, _} = Map.split(args, [:name, :description])

    case Report.save_report(report, params) do
      {:ok, report} -> {:ok, report}
      {:error, _reason} -> {:error, "Can't save report!"}
    end
  end

  def get_reports(_root, _args, %{context: %{auth: %{current_user: user}}}) do
    plan = get_user_plan(user.id)

    reports = Report.get_published_reports(%{is_logged_in: true, plan_name: plan})

    {:ok, reports}
  end

  def get_reports(_root, _args, _resolution) do
    {:ok, Report.get_published_reports(%{is_logged_in: false})}
  end

  def get_reports_by_tags(_root, %{tags: tags}, %{context: %{auth: %{current_user: user}}}) do
    plan = get_user_plan(user.id)

    reports = Report.get_by_tags(tags, %{is_logged_in: true, plan_name: plan})

    {:ok, reports}
  end

  def get_reports_by_tags(_root, %{tags: tags}, _resolution) do
    {:ok, Report.get_by_tags(tags, %{is_logged_in: false})}
  end

  defp get_user_plan(user_id) do
    case Subscription.current_subscription_plan(user_id, Product.product_sanbase()) do
      "FREE" -> Subscription.current_subscription_plan(user_id, Product.product_api())
      sanbase_plan -> sanbase_plan
    end
  end
end
