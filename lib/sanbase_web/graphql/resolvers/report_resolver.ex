defmodule SanbaseWeb.Graphql.Resolvers.ReportResolver do
  alias Sanbase.Report
  alias Sanbase.Billing
  alias Sanbase.Billing.Product

  def upload_report(_root, %{report: report} = args, _resolution) do
    {params, _} = Map.split(args, [:name, :description])

    case Report.save_report(report, params) do
      {:ok, report} -> {:ok, report}
      {:error, _reason} -> {:error, "Can't save report!"}
    end
  end

  def get_reports(_root, _args, %{context: %{auth: %{current_user: user}}}) do
    reports = Report.get_published_reports(%{is_logged_in: true, paid_plan?: paid_plan?(user)})

    {:ok, reports}
  end

  def get_reports(_root, _args, _resolution) do
    {:ok, Report.get_published_reports(%{is_logged_in: false})}
  end

  def get_reports_by_tags(_root, %{tags: tags}, %{context: %{auth: %{current_user: user}}}) do
    reports = Report.get_by_tags(tags, %{is_logged_in: true, paid_plan?: paid_plan?(user)})

    {:ok, reports}
  end

  def get_reports_by_tags(_root, %{tags: tags}, _resolution) do
    {:ok, Report.get_by_tags(tags, %{is_logged_in: false})}
  end

  # A paid plan on either product unlocks the pro reports
  defp paid_plan?(user) do
    Billing.user_has_product_access?(user.id, Product.product_sanbase()) or
      Billing.user_has_product_access?(user.id, Product.product_api())
  end
end
