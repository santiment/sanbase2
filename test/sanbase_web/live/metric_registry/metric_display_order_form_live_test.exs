defmodule SanbaseWeb.MetricDisplayOrderFormLiveTest do
  use SanbaseWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanbase.Factory

  alias Sanbase.Metric.UIMetadata.DisplayOrder
  alias Sanbase.Metric.UIMetadata.Category

  describe "args JSON editing" do
    setup do
      user = insert(:user)
      metric_registry_role = insert(:role_metric_registry_owner)
      admin_role = insert(:role_admin_panel_viewer)
      Sanbase.Accounts.UserRole.create(user.id, metric_registry_role.id)
      Sanbase.Accounts.UserRole.create(user.id, admin_role.id)
      {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)
      conn = Plug.Test.init_test_session(build_conn(), jwt_tokens)

      {:ok, category} = Category.create(%{name: "Test Category", display_order: 1})

      {:ok, metric} =
        DisplayOrder.add_metric(
          "test_metric",
          category.id,
          nil,
          ui_human_readable_name: "Test Metric",
          chart_style: "line",
          unit: "usd",
          description: "A test metric"
        )

      {:ok, conn: conn, metric: metric, category: category}
    end

    test "displays empty args field when metric has no args", %{conn: conn, metric: metric} do
      {:ok, _view, html} = live(conn, "/admin/metric_registry/display_order/edit/#{metric.id}")

      assert html =~ "Args (JSON)"
      assert html =~ ~s|placeholder|
    end

    test "displays existing args as JSON", %{conn: conn, metric: metric} do
      args = %{"selector" => %{"slug" => "ethereum"}}
      {:ok, updated_metric} = DisplayOrder.do_update(metric, %{args: args})

      {:ok, _view, html} =
        live(conn, "/admin/metric_registry/display_order/edit/#{updated_metric.id}")

      assert html =~ "ethereum"
      assert html =~ "selector"
    end

    test "saves valid JSON args", %{conn: conn, metric: metric} do
      {:ok, view, _html} = live(conn, "/admin/metric_registry/display_order/edit/#{metric.id}")

      form_data = %{
        "ui_human_readable_name" => "Test Metric",
        "category_id" => to_string(metric.category_id),
        "group_id" => "",
        "chart_style" => "line",
        "unit" => "usd",
        "description" => "A test metric",
        "args" => ~s|{"selector": {"slug": "ethereum"}}|
      }

      view
      |> form("form", form_data)
      |> render_submit()

      updated = DisplayOrder.by_id(metric.id)
      assert updated.args == %{"selector" => %{"slug" => "ethereum"}}
    end

    test "shows error for invalid JSON", %{conn: conn, metric: metric} do
      {:ok, view, _html} = live(conn, "/admin/metric_registry/display_order/edit/#{metric.id}")

      form_data = %{
        "ui_human_readable_name" => "Test Metric",
        "category_id" => to_string(metric.category_id),
        "group_id" => "",
        "chart_style" => "line",
        "unit" => "usd",
        "description" => "A test metric",
        "args" => ~s|{invalid json}|
      }

      html =
        view
        |> form("form", form_data)
        |> render_submit()

      assert html =~ "Invalid JSON"
    end

    test "accepts empty args", %{conn: conn, metric: metric} do
      {:ok, updated_metric} =
        DisplayOrder.do_update(metric, %{args: %{"selector" => %{"slug" => "bitcoin"}}})

      {:ok, view, _html} =
        live(conn, "/admin/metric_registry/display_order/edit/#{updated_metric.id}")

      form_data = %{
        "ui_human_readable_name" => "Test Metric",
        "category_id" => to_string(updated_metric.category_id),
        "group_id" => "",
        "chart_style" => "line",
        "unit" => "usd",
        "description" => "A test metric",
        "args" => ""
      }

      view
      |> form("form", form_data)
      |> render_submit()

      cleared = DisplayOrder.by_id(updated_metric.id)
      assert cleared.args == %{}
    end
  end
end
