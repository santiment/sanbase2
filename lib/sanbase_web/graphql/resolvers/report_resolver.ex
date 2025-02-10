defmodule SanbaseWeb.Graphql.Resolvers.ReportResolver do
  @moduledoc false
  alias Sanbase.Billing.Product
  alias Sanbase.Billing.Subscription
  alias Sanbase.Report

  require Logger

  def upload_report(_root, %{report: report} = args, _resolution) do
    {params, _} = Map.split(args, [:name, :description])

    case Report.save_report(report, params) do
      {:ok, report} -> {:ok, report}
      {:error, _reason} -> {:error, "Can't save report!"}
    end
  end

  def get_reports(_root, _args, %{context: %{auth: %{current_user: user}}}) do
    plan = Subscription.current_subscription_plan(user.id, Product.product_sanbase())

    reports = Report.get_published_reports(%{is_logged_in: true, plan_name: plan})

    {:ok, reports}
  end

  def get_reports(_root, _args, _resolution) do
    {:ok, Report.get_published_reports(%{is_logged_in: false})}
  end

  def get_reports_by_tags(_root, %{tags: tags}, %{context: %{auth: %{current_user: user}}}) do
    plan = Subscription.current_subscription_plan(user.id, Product.product_sanbase())

    reports = Report.get_by_tags(tags, %{is_logged_in: true, plan_name: plan})

    {:ok, reports}
  end

  def get_reports_by_tags(_root, %{tags: tags}, _resolution) do
    {:ok, Report.get_by_tags(tags, %{is_logged_in: false})}
  end
end
