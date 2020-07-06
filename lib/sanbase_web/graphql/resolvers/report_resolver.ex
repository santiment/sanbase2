defmodule SanbaseWeb.Graphql.Resolvers.ReportResolver do
  require Logger

  alias Sanbase.Report
  alias Sanbase.Billing.{Subscription, Product}

  @product_sanbase Product.product_sanbase()

  def upload_report(_root, %{report: report}, _resolution) do
    Report.save_report(report)
  end

  def list_reports(_root, _args, %{context: %{auth: %{current_user: user}}}) do
    reports =
      Subscription.current_subscription(user, @product_sanbase)
      |> Report.list_published_reports()

    {:ok, reports}
  end
end
