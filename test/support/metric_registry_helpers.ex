defmodule Sanbase.MetricRegistryHelpers do
  @moduledoc """
  Test helpers for the metric registry admin tests: creating registry rows and
  building an authenticated admin conn.
  """

  @doc """
  Returns a conn authenticated as a user carrying the metric registry owner and
  admin panel viewer roles, ready for `live/2` calls against the metric
  registry admin pages.
  """
  def metric_registry_admin_conn() do
    user = Sanbase.Factory.insert(:user)
    metric_registry_role = Sanbase.Factory.insert(:role_metric_registry_owner)
    admin_role = Sanbase.Factory.insert(:role_admin_panel_viewer)
    Sanbase.Accounts.UserRole.create(user.id, metric_registry_role.id)
    Sanbase.Accounts.UserRole.create(user.id, admin_role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)

    Plug.Test.init_test_session(Phoenix.ConnTest.build_conn(), jwt_tokens)
  end

  @doc """
  Creates a metric registry row. Accepts a metric name or an attrs map with a
  required `:metric` key; any other attrs override the defaults.
  """
  def create_registry_metric(metric) when is_binary(metric) do
    create_registry_metric(%{metric: metric})
  end

  def create_registry_metric(attrs) when is_map(attrs) do
    defaults = %{
      internal_metric: Map.fetch!(attrs, :metric) <> "_internal",
      human_readable_name: "Human name",
      min_interval: "5m",
      tables: [%{name: "daily_metrics_v2"}],
      default_aggregation: "avg",
      access: "free",
      has_incomplete_data: false,
      data_type: "timeseries"
    }

    {:ok, registry} = Sanbase.Metric.Registry.create(Map.merge(defaults, attrs))
    registry
  end
end
