defmodule SanbaseWeb.Graphql.MenuApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    user2 = insert(:user)
    {:ok, query} = Sanbase.Queries.create_query(%{name: "Query"}, user.id)
    {:ok, dashboard} = Sanbase.Dashboards.create_dashboard(%{name: "Dashboard"}, user.id)

    conn = setup_jwt_auth(build_conn(), user)
    conn2 = setup_jwt_auth(build_conn(), user2)

    %{
      conn: conn,
      conn2: conn2,
      user: user,
      user2: user2,
      query: query,
      dashboard: dashboard
    }
  end

  test "create, update and get menu", context do
    menu =
      context.conn
      |> menu_mutation(:create_menu, %{name: "MyMenu", description: "Desc"})
      |> get_in(["data", "createMenu"])

    assert {:ok, _} = Sanbase.Menus.get_menu(menu["entityId"], context.user.id)

    assert %{
             "description" => "Desc",
             "entityId" => _,
             "entityType" => "menu",
             "menuItemId" => nil,
             "menuItems" => [],
             "name" => "MyMenu"
           } = menu

    menu =
      context.conn
      |> menu_mutation(:update_menu, %{id: menu["entityId"], name: "MyMenu2"})
      |> get_in(["data", "updateMenu"])

    assert menu["name"] == "MyMenu2"

    # Get the menu
    menu = context.conn |> get_menu(menu["entityId"]) |> get_in(["data", "getMenu"])

    assert %{
             "description" => "Desc",
             "entityId" => _,
             "entityType" => "menu",
             "menuItemId" => nil,
             "menuItems" => [],
             "name" => "MyMenu2"
           } = menu

    # Another user cannot update the menu
    error_msg =
      context.conn2
      |> menu_mutation(:update_menu, %{id: menu["entityId"], name: "MyMenu3"})
      |> get_in(["errors", Access.at(0), "message"])

    assert error_msg =~ "not found or it is owned by another user"
    # Another user cannot obtain the menu
    error_msg =
      context.conn2
      |> get_menu(menu["entityId"])
      |> get_in(["errors", Access.at(0), "message"])

    assert error_msg =~ "not found or it is owned by another user"
  end

  test "delete menu", context do
    menu =
      context.conn
      |> menu_mutation(:create_menu, %{name: "MyMenu", description: "Desc"})
      |> get_in(["data", "createMenu"])

    assert {:ok, _} = Sanbase.Menus.get_menu(menu["entityId"], context.user.id)

    # Other users cannot delete the menu
    error_msg =
      context.conn2
      |> menu_mutation(:delete_menu, %{id: menu["entityId"]})
      |> get_in(["errors", Access.at(0), "message"])

    assert error_msg =~ "not found or it is owned by another user"

    assert {:ok, _} = Sanbase.Menus.get_menu(menu["entityId"], context.user.id)

    # The owner can delete the menu
    menu =
      context.conn
      |> menu_mutation(:delete_menu, %{id: menu["entityId"]})
      |> get_in(["data", "deleteMenu"])

    assert %{"entityId" => _} = menu

    assert {:error, _} = Sanbase.Menus.get_menu(menu["entityId"], context.user.id)
  end

  test "add and get nested menu items", context do
    menu =
      context.conn
      |> menu_mutation(:create_menu, %{name: "MyMenu", description: "Desc"})
      |> get_in(["data", "createMenu"])

    ## Add menu items to the top-level menu

    # This will also internally call create_menu_item and add it as a menu
    sub_menu =
      context.conn
      |> menu_mutation(:create_menu, %{
        name: "SubMenu",
        description: "Desc",
        parent_id: menu["entityId"],
        position: 1
      })
      |> get_in(["data", "createMenu"])

    _ =
      context.conn
      |> menu_mutation(:create_menu_item, %{
        parent_id: menu["entityId"],
        entity: %{query_id: context.query.id, map_as_input_object: true},
        # this will force it to be put in front of the sub-menu added above
        # the sub_menu will have position 2
        position: 1
      })
      |> get_in(["data", "createMenuItem"])

    # Add a menu item without providing position. It will be added to the end
    # and will get a position 3
    _ =
      context.conn
      |> menu_mutation(:create_menu_item, %{
        parent_id: menu["entityId"],
        entity: %{query_id: context.query.id, map_as_input_object: true}
      })
      |> get_in(["data", "createMenuItem"])

    ## Add items to the sub-menu
    _ =
      context.conn
      |> menu_mutation(:create_menu_item, %{
        parent_id: sub_menu["entityId"],
        entity: %{query_id: context.query.id, map_as_input_object: true}
      })
      |> get_in(["data", "createMenuItem"])

    _ =
      context.conn
      |> menu_mutation(:create_menu_item, %{
        parent_id: sub_menu["entityId"],
        entity: %{dashboard_id: context.dashboard.id, map_as_input_object: true},
        position: 1
      })
      |> get_in(["data", "createMenuItem"])

    # Fetch the top-level menu again
    menu = context.conn |> get_menu(menu["entityId"]) |> get_in(["data", "getMenu"])

    root_menu_id = menu["entityId"]
    query_id = context.query.id
    dashboard_id = context.dashboard.id
    sub_menu_id = sub_menu["entityId"]

    assert %{
             "description" => "Desc",
             "entityId" => ^root_menu_id,
             "entityType" => "menu",
             "menuItemId" => nil,
             "menuItems" => [
               %{
                 "description" => nil,
                 "entityId" => ^query_id,
                 "entityType" => "query",
                 "menuItemId" => _,
                 "name" => "Query",
                 "position" => 1
               },
               %{
                 "description" => "Desc",
                 "entityId" => ^sub_menu_id,
                 "entityType" => "menu",
                 "menuItemId" => _,
                 "menuItems" => [
                   %{
                     "description" => nil,
                     "entityId" => ^dashboard_id,
                     "entityType" => "dashboard",
                     "menuItemId" => _,
                     "name" => "Dashboard",
                     "position" => 1
                   },
                   %{
                     "description" => nil,
                     "entityId" => ^query_id,
                     "entityType" => "query",
                     "menuItemId" => _,
                     "name" => "Query",
                     "position" => 2
                   }
                 ],
                 "name" => "SubMenu",
                 "position" => 2
               },
               %{
                 "description" => nil,
                 "entityId" => ^query_id,
                 "entityType" => "query",
                 "menuItemId" => _,
                 "name" => "Query",
                 "position" => 3
               }
             ],
             "name" => "MyMenu"
           } = menu
  end

  test "update and delete menu items", context do
    menu =
      context.conn
      |> menu_mutation(:create_menu, %{name: "MyMenu", description: "Desc"})
      |> get_in(["data", "createMenu"])

    sub_menu =
      context.conn
      |> menu_mutation(:create_menu, %{
        name: "SubMenu",
        description: "Desc",
        parent_id: menu["entityId"]
      })
      |> get_in(["data", "createMenu"])

    _ =
      menu_mutation(context.conn, :create_menu_item, %{
        parent_id: sub_menu["entityId"],
        entity: %{query_id: context.query.id, map_as_input_object: true}
      })

    _ =
      menu_mutation(context.conn, :create_menu_item, %{
        parent_id: menu["entityId"],
        entity: %{query_id: context.query.id, map_as_input_object: true}
      })

    _ =
      menu_mutation(context.conn, :create_menu_item, %{
        parent_id: menu["entityId"],
        entity: %{dashboard_id: context.dashboard.id, map_as_input_object: true}
      })

    menu = context.conn |> get_menu(menu["entityId"]) |> get_in(["data", "getMenu"])

    root_menu_id = menu["entityId"]
    sub_menu_id = sub_menu["entityId"]
    query_id = context.query.id
    dashboard_id = context.dashboard.id

    # Check the first ordering of the menu items
    assert %{
             "description" => "Desc",
             "entityId" => ^root_menu_id,
             "entityType" => "menu",
             "menuItemId" => nil,
             "menuItems" => [
               %{
                 "description" => "Desc",
                 "entityId" => ^sub_menu_id,
                 "entityType" => "menu",
                 "menuItemId" => _,
                 "name" => "SubMenu",
                 "position" => 1,
                 "menuItems" => [
                   %{
                     "description" => nil,
                     "entityId" => ^query_id,
                     "entityType" => "query",
                     "menuItemId" => sub_menu_query_menu_item_id,
                     "name" => "Query",
                     "position" => 1
                   }
                 ]
               },
               %{
                 "description" => nil,
                 "entityId" => ^query_id,
                 "entityType" => "query",
                 "menuItemId" => _,
                 "name" => "Query",
                 "position" => 2
               },
               %{
                 "description" => nil,
                 "entityId" => ^dashboard_id,
                 "entityType" => "dashboard",
                 "menuItemId" => dashboard_menu_item_id,
                 "name" => "Dashboard",
                 "position" => 3
               }
             ],
             "name" => "MyMenu"
           } = menu

    # Delete one of the menu items of the root menu
    _ =
      menu_mutation(context.conn, :delete_menu_item, %{
        id: dashboard_menu_item_id
      })

    # Move the sub-menu item to the root menu at position 1
    _ =
      menu_mutation(context.conn, :update_menu_item, %{
        id: sub_menu_query_menu_item_id,
        parent_id: menu["entityId"],
        position: 1
      })

    # Check again the new ordering of the menu items
    menu = context.conn |> get_menu(menu["entityId"]) |> get_in(["data", "getMenu"])

    # The dashboard root-menu item is removed and the only sub-menu item is moved to the root menu
    # at position one, bumping the position of the rest of the items
    assert %{
             "description" => "Desc",
             "entityId" => ^root_menu_id,
             "entityType" => "menu",
             "menuItemId" => nil,
             "menuItems" => [
               %{
                 "description" => nil,
                 "entityId" => ^query_id,
                 "entityType" => "query",
                 "menuItemId" => ^sub_menu_query_menu_item_id,
                 "name" => "Query",
                 "position" => 1
               },
               %{
                 "description" => "Desc",
                 "entityId" => ^sub_menu_id,
                 "entityType" => "menu",
                 "menuItemId" => _,
                 "name" => "SubMenu",
                 "position" => 2,
                 "menuItems" => []
               },
               %{
                 "description" => nil,
                 "entityId" => ^query_id,
                 "entityType" => "query",
                 "menuItemId" => _,
                 "name" => "Query",
                 "position" => 3
               }
             ],
             "name" => "MyMenu"
           } = menu
  end

  defp get_menu(conn, menu_id) do
    query = "{ getMenu(id: #{menu_id}) }"

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp menu_mutation(conn, mutation, params) do
    mutation_name = Inflex.camelize(mutation, :lower)

    mutation = """
      mutation {
        #{mutation_name}(#{map_to_args(params)})
      }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end
end
