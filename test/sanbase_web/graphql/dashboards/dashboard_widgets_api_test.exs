defmodule Sanbase.DashboardsWidgetsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn, user: user}
  end

  describe "Dashboards Text Widget" do
    test "create", context do
      {:ok, %{id: dashboard_id}} =
        Sanbase.Dashboards.create_dashboard(%{name: "My Dashboard"}, context.user.id)

      # The dashboard mutation can run any mutation that returns a dashboard as a result
      result =
        context.conn
        |> execute_dashboard_text_widget_mutation(:add_dashboard_text_widget, %{
          dashboard_id: dashboard_id,
          name: "My First Text Widget",
          description: "desc",
          body: "body"
        })
        |> get_in(["data", "addDashboardTextWidget"])

      assert %{
               "id" => ^dashboard_id,
               "name" => "My Dashboard",
               "settings" => %{},
               "textWidgets" => [
                 %{
                   "body" => "body",
                   "description" => "desc",
                   "id" => <<_::binary>>,
                   "name" => "My First Text Widget"
                 }
               ],
               "user" => %{"id" => _}
             } = result["dashboard"]

      {:ok, fetched_dashboard} = Sanbase.Dashboards.get_dashboard(dashboard_id, context.user.id)

      assert length(fetched_dashboard.text_widgets) == 1
      [text_widget] = fetched_dashboard.text_widgets
      assert %{body: "body", description: "desc", name: "My First Text Widget"} = text_widget
    end

    test "update", context do
      {:ok, %{id: dashboard_id}} =
        Sanbase.Dashboards.create_dashboard(%{name: "My Dashboard"}, context.user.id)

      {:ok, %{text_widget: %{id: text_widget_id}}} =
        Sanbase.Dashboards.add_text_widget(dashboard_id, context.user.id, %{
          name: "name",
          description: "description",
          body: "body"
        })

      # The dashboard mutation can run any mutation that returns a dashboard as a result
      result =
        context.conn
        |> execute_dashboard_text_widget_mutation(:update_dashboard_text_widget, %{
          dashboard_id: dashboard_id,
          text_widget_id: text_widget_id,
          name: "Updated name",
          description: "Updated desc"
        })
        |> get_in(["data", "updateDashboardTextWidget"])

      assert %{
               "id" => ^dashboard_id,
               "name" => "My Dashboard",
               "settings" => %{},
               "textWidgets" => [
                 %{
                   "id" => ^text_widget_id,
                   "body" => "body",
                   "description" => "Updated desc",
                   "name" => "Updated name"
                 }
               ]
             } = result["dashboard"]

      assert %{
               "id" => ^text_widget_id,
               "body" => "body",
               "description" => "Updated desc",
               "name" => "Updated name"
             } = result["textWidget"]

      {:ok, fetched_dashboard} = Sanbase.Dashboards.get_dashboard(dashboard_id, context.user.id)

      assert length(fetched_dashboard.text_widgets) == 1
      [text_widget] = fetched_dashboard.text_widgets
      assert %{body: "body", description: "Updated desc", name: "Updated name"} = text_widget
    end

    test "delete", context do
      {:ok, %{id: dashboard_id}} =
        Sanbase.Dashboards.create_dashboard(%{name: "My Dashboard"}, context.user.id)

      {:ok, %{text_widget: %{id: text_widget_id}}} =
        Sanbase.Dashboards.add_text_widget(dashboard_id, context.user.id, %{
          name: "name",
          description: "description",
          body: "body"
        })

      result =
        context.conn
        |> execute_dashboard_text_widget_mutation(:delete_dashboard_text_widget, %{
          dashboard_id: dashboard_id,
          text_widget_id: text_widget_id
        })
        |> get_in(["data", "deleteDashboardTextWidget"])

      assert %{
               "id" => ^dashboard_id,
               "name" => "My Dashboard",
               "settings" => %{},
               "textWidgets" => []
             } = result["dashboard"]

      assert %{
               "id" => ^text_widget_id,
               "body" => "body",
               "description" => "description",
               "name" => "name"
             } = result["textWidget"]

      {:ok, fetched_dashboard} = Sanbase.Dashboards.get_dashboard(dashboard_id, context.user.id)

      assert length(fetched_dashboard.text_widgets) == 0
    end

    defp execute_dashboard_text_widget_mutation(conn, mutation, args) do
      mutation_name = Inflex.camelize(mutation, :lower)

      mutation = """
      mutation {
        #{mutation_name}(#{map_to_args(args)}){
          dashboard {
            id
            name
            description
            user { id }
            textWidgets { id name description body }
            settings
          }
          textWidget {
            id
            name
            description
            body
          }
        }
      }
      """

      conn
      |> post("/graphql", mutation_skeleton(mutation))
      |> json_response(200)
    end
  end

  describe "Dashboards Image Widget" do
    test "create", context do
      {:ok, %{id: dashboard_id}} =
        Sanbase.Dashboards.create_dashboard(%{name: "My Dashboard"}, context.user.id)

      # The dashboard mutation can run any mutation that returns a dashboard as a result
      result =
        context.conn
        |> execute_dashboard_image_widget_mutation(:add_dashboard_image_widget, %{
          dashboard_id: dashboard_id,
          url: "https://example.com/image.png",
          alt: "some image"
        })
        |> get_in(["data", "addDashboardImageWidget"])

      assert %{
               "id" => ^dashboard_id,
               "name" => "My Dashboard",
               "settings" => %{},
               "imageWidgets" => [
                 %{
                   "url" => "https://example.com/image.png",
                   "alt" => "some image",
                   "id" => <<_::binary>>
                 }
               ],
               "user" => %{"id" => _}
             } = result["dashboard"]

      {:ok, fetched_dashboard} = Sanbase.Dashboards.get_dashboard(dashboard_id, context.user.id)

      assert length(fetched_dashboard.image_widgets) == 1
      [image_widget] = fetched_dashboard.image_widgets
      assert %{url: "https://example.com/image.png", alt: "some image"} = image_widget
    end

    test "update", context do
      {:ok, %{id: dashboard_id}} =
        Sanbase.Dashboards.create_dashboard(%{name: "My Dashboard"}, context.user.id)

      {:ok, %{image_widget: %{id: image_widget_id}}} =
        Sanbase.Dashboards.add_image_widget(dashboard_id, context.user.id, %{
          url: "http://example.com/image.png",
          alt: "some image"
        })

      # The dashboard mutation can run any mutation that returns a dashboard as a result
      result =
        context.conn
        |> execute_dashboard_image_widget_mutation(:update_dashboard_image_widget, %{
          dashboard_id: dashboard_id,
          image_widget_id: image_widget_id,
          alt: "Updated alt text"
        })
        |> get_in(["data", "updateDashboardImageWidget"])

      assert %{
               "id" => ^dashboard_id,
               "name" => "My Dashboard",
               "settings" => %{},
               "imageWidgets" => [
                 %{
                   "id" => ^image_widget_id,
                   "url" => "http://example.com/image.png",
                   "alt" => "Updated alt text"
                 }
               ]
             } = result["dashboard"]

      assert %{
               "id" => ^image_widget_id,
               "url" => "http://example.com/image.png",
               "alt" => "Updated alt text"
             } = result["imageWidget"]

      {:ok, fetched_dashboard} = Sanbase.Dashboards.get_dashboard(dashboard_id, context.user.id)

      assert length(fetched_dashboard.image_widgets) == 1
      [image_widget] = fetched_dashboard.image_widgets
      assert %{url: "http://example.com/image.png", alt: "Updated alt text"} = image_widget
    end

    test "delete", context do
      {:ok, %{id: dashboard_id}} =
        Sanbase.Dashboards.create_dashboard(%{name: "My Dashboard"}, context.user.id)

      {:ok, %{image_widget: %{id: image_widget_id}}} =
        Sanbase.Dashboards.add_image_widget(dashboard_id, context.user.id, %{
          url: "http://example.com/image.png",
          alt: "some image"
        })

      result =
        context.conn
        |> execute_dashboard_image_widget_mutation(:delete_dashboard_image_widget, %{
          dashboard_id: dashboard_id,
          image_widget_id: image_widget_id
        })
        |> get_in(["data", "deleteDashboardImageWidget"])

      assert %{
               "id" => ^dashboard_id,
               "name" => "My Dashboard",
               "settings" => %{},
               "imageWidgets" => []
             } = result["dashboard"]

      assert %{
               "id" => ^image_widget_id,
               "url" => "http://example.com/image.png",
               "alt" => "some image"
             } = result["imageWidget"]

      {:ok, fetched_dashboard} = Sanbase.Dashboards.get_dashboard(dashboard_id, context.user.id)

      assert length(fetched_dashboard.image_widgets) == 0
    end

    defp execute_dashboard_image_widget_mutation(conn, mutation, args) do
      mutation_name = Inflex.camelize(mutation, :lower)

      mutation = """
      mutation {
        #{mutation_name}(#{map_to_args(args)}){
          dashboard {
            id
            name
            description
            user { id }
            imageWidgets { id url alt }
            settings
          }
          imageWidget {
            id
            url
            alt
          }
        }
      }
      """

      conn
      |> post("/graphql", mutation_skeleton(mutation))
      |> json_response(200)
    end
  end
end
