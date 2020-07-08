defmodule SanbaseWeb.Graphql.Resolvers.ReportResolver do
  require Logger

  alias Sanbase.Report
  alias Sanbase.Billing.{Subscription, Product}

  @product_sanbase Product.product_sanbase()

  def upload_report(_root, %{report: report} = args, _resolution) do
    {params, _} = Map.split(args, [:name, :description])
    Report.save_report(report, params)
  end

  def get_reports(_root, _args, %{context: %{auth: %{current_user: user}}}) do
    reports =
      Subscription.current_subscription(user, @product_sanbase)
      |> Report.get_published_reports()

    {:ok, reports}
  end
end
