defmodule SanbaseWeb.Graphql.TableConfigurationApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)
    user2 = insert(:user)

    conn_no_user = build_conn()
    conn = setup_jwt_auth(build_conn(), user)
    conn2 = setup_jwt_auth(build_conn(), user2)

    settings = %{
      title: "My table configuration",
      type: :project,
      description: "some description",
      is_public: false,
      page_size: 50,
      columns: %{
        "daily_active_addresses" => %{
          "from" => "30d ago",
          "to" => "now"
        }
      }
    }

    %{
      conn: conn,
      conn2: conn2,
      conn_no_user: conn_no_user,
      user: user,
      user2: user2,
      settings: settings
    }
  end

  describe "table configuration mutations" do
    test "create", context do
      %{user: user, conn: conn, settings: settings} = context

      table_configuration =
        create_table_configuration(conn, settings)
        |> get_in(["data", "createTableConfiguration"])

      assert table_configuration["title"] == settings.title
      assert table_configuration["type"] == settings.type |> Atom.to_string() |> String.upcase()
      assert table_configuration["description"] == settings.description
      assert table_configuration["isPublic"] == settings.is_public
      assert table_configuration["pageSize"] == settings.page_size
      assert table_configuration["columns"] == settings.columns
      assert table_configuration["user"]["id"] |> String.to_integer() == user.id
      assert table_configuration["user"]["email"] == user.email
    end

    test "update", context do
      %{conn: conn, settings: settings} = context

      table_configuration_id =
        create_table_configuration(conn, settings)
        |> get_in(["data", "createTableConfiguration", "id"])

      new_settings = %{
        title: "New Title",
        type: :blockchain_address,
        description: "New description",
        is_public: true,
        page_size: 150,
        columns: %{"columns" => ["a", "b", "c"]}
      }

      table_configuration =
        update_table_configuration(conn, table_configuration_id, new_settings)
        |> get_in(["data", "updateTableConfiguration"])

      assert table_configuration["title"] == new_settings.title

      assert table_configuration["type"] ==
               new_settings.type |> Atom.to_string() |> String.upcase()

      assert table_configuration["description"] == new_settings.description
      assert table_configuration["isPublic"] == new_settings.is_public
      assert table_configuration["pageSize"] == new_settings.page_size
      assert table_configuration["columns"] == new_settings.columns
    end

    test "cannot update other user's table configuration", context do
      %{conn: conn, conn2: conn2, settings: settings} = context

      table_configuration_id =
        create_table_configuration(conn, settings)
        |> get_in(["data", "createTableConfiguration", "id"])

      error_msg =
        update_table_configuration(conn2, table_configuration_id, %{title: "New Title"})
        |> get_in(["errors"])
        |> hd()
        |> Map.get("message")

      assert error_msg =~ "not owned by the user"
    end

    test "delete", context do
      %{conn: conn, settings: settings} = context

      table_configuration_id =
        create_table_configuration(conn, settings)
        |> get_in(["data", "createTableConfiguration", "id"])

      _ = delete_table_configuration(conn, table_configuration_id)
      {:error, error_msg} = Sanbase.TableConfiguration.by_id(table_configuration_id, [])
      assert error_msg =~ "does not exist"
    end
  end

  describe "table configuration queries" do
    test "can query with anonymous user", context do
      %{conn: conn, conn_no_user: conn_no_user, settings: settings} = context

      # Create a public and private table configuration

      table_configuration_id1 =
        create_table_configuration(conn, %{settings | is_public: true})
        |> get_in(["data", "createTableConfiguration", "id"])

      table_configuration_id2 =
        create_table_configuration(conn, %{settings | is_public: false})
        |> get_in(["data", "createTableConfiguration", "id"])

      # Test fetching table configurations with no logged in user

      table_configuration1 =
        get_table_configuration(conn_no_user, table_configuration_id1)
        |> get_in(["data", "tableConfiguration"])

      assert table_configuration1["id"] == table_configuration_id1

      table_configuration2 =
        get_table_configuration(conn_no_user, table_configuration_id2)
        |> get_in(["data", "tableConfiguration"])

      assert table_configuration2 == nil

      table_configuration_ids =
        get_table_configurations(conn_no_user, nil)
        |> get_in(["data", "tableConfigurations"])
        |> Enum.map(& &1["id"])

      assert table_configuration_ids == [table_configuration_id1]
    end

    test "can get all fields", context do
      %{user: user, conn: conn, settings: settings} = context

      table_configuration_id =
        create_table_configuration(conn, settings)
        |> get_in(["data", "createTableConfiguration", "id"])

      table_configuration =
        get_table_configuration(conn, table_configuration_id)
        |> get_in(["data", "tableConfiguration"])

      assert table_configuration["title"] == settings.title
      assert table_configuration["type"] == settings.type |> Atom.to_string() |> String.upcase()
      assert table_configuration["description"] == settings.description
      assert table_configuration["isPublic"] == settings.is_public
      assert table_configuration["pageSize"] == settings.page_size
      assert table_configuration["user"]["id"] |> String.to_integer() == user.id
      assert table_configuration["user"]["email"] == user.email
      assert table_configuration["columns"] == settings.columns
    end

    test "get own public table configuration", context do
      %{conn: conn, settings: settings} = context
      settings = Map.put(settings, :is_public, true)

      table_configuration_id =
        create_table_configuration(conn, settings)
        |> get_in(["data", "createTableConfiguration", "id"])

      table_configuration =
        get_table_configuration(conn, table_configuration_id)
        |> get_in(["data", "tableConfiguration"])

      assert table_configuration["id"] == table_configuration_id
    end

    test "get own private table configuration", context do
      %{conn: conn, settings: settings} = context
      settings = Map.put(settings, :is_public, true)

      table_configuration_id =
        create_table_configuration(conn, settings)
        |> get_in(["data", "createTableConfiguration", "id"])

      table_configuration =
        get_table_configuration(conn, table_configuration_id)
        |> get_in(["data", "tableConfiguration"])

      assert table_configuration["id"] == table_configuration_id
    end

    test "get other user's public table configuration", context do
      %{conn: conn, conn2: conn2, settings: settings} = context
      settings = Map.put(settings, :is_public, true)

      table_configuration_id =
        create_table_configuration(conn, settings)
        |> get_in(["data", "createTableConfiguration", "id"])

      table_configuration =
        get_table_configuration(conn2, table_configuration_id)
        |> get_in(["data", "tableConfiguration"])

      assert table_configuration["id"] == table_configuration_id
    end

    test "cannot get other user's private table configuration", context do
      %{conn: conn, conn2: conn2, settings: settings} = context
      settings = Map.put(settings, :is_public, true)

      table_configuration_id =
        create_table_configuration(conn, settings)
        |> get_in(["data", "createTableConfiguration", "id"])

      error_msg =
        update_table_configuration(conn2, table_configuration_id, %{title: "New Title"})
        |> get_in(["errors"])
        |> hd()
        |> Map.get("message")

      assert error_msg =~ "not owned by the user"
    end

    test "get all table configurations", context do
      %{conn: conn, conn2: conn2, settings: settings} = context
      settings = Map.put(settings, :is_public, true)

      [
        table_configuration_id1,
        table_configuration_id2,
        table_configuration_id3,
        table_configuration_id4
      ] =
        [
          create_table_configuration(conn, settings),
          create_table_configuration(conn, settings),
          create_table_configuration(conn2, settings),
          create_table_configuration(conn2, settings |> Map.put(:is_public, false))
        ]
        |> Enum.map(&get_in(&1, ["data", "createTableConfiguration", "id"]))

      table_configuration_ids =
        get_table_configurations(conn, nil)
        |> get_in(["data", "tableConfigurations"])
        |> Enum.map(& &1["id"])

      assert table_configuration_id1 in table_configuration_ids
      assert table_configuration_id2 in table_configuration_ids
      assert table_configuration_id3 in table_configuration_ids
      refute table_configuration_id4 in table_configuration_ids
    end

    test "get all table configurations of a user", context do
      %{conn: conn, conn2: conn2, user2: user2, settings: settings} = context
      settings = Map.put(settings, :is_public, true)

      [
        table_configuration_id1,
        table_configuration_id2,
        table_configuration_id3,
        table_configuration_id4
      ] =
        [
          create_table_configuration(conn, settings),
          create_table_configuration(conn, settings),
          create_table_configuration(conn2, settings),
          create_table_configuration(conn2, %{settings | is_public: false})
        ]
        |> Enum.map(&get_in(&1, ["data", "createTableConfiguration", "id"]))

      # User gets their own public and private table configurations
      table_configuration_ids =
        get_table_configurations(conn2, user2.id)
        |> get_in(["data", "tableConfigurations"])
        |> Enum.map(& &1["id"])

      refute table_configuration_id1 in table_configuration_ids
      refute table_configuration_id2 in table_configuration_ids
      assert table_configuration_id3 in table_configuration_ids
      assert table_configuration_id4 in table_configuration_ids

      # Get only public table configurations of another user
      table_configuration_ids =
        get_table_configurations(conn, user2.id)
        |> get_in(["data", "tableConfigurations"])
        |> Enum.map(& &1["id"])

      assert length(table_configuration_ids) == 1
      assert table_configuration_id3 in table_configuration_ids
    end
  end

  # Private functions

  defp create_table_configuration(conn, settings) do
    query = """
    mutation {
      createTableConfiguration(settings: #{map_to_input_object_str(settings)}) {
        id
        title
        type
        isPublic
        description
        pageSize
        user{ id email }
        columns
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(query))
    |> json_response(200)
  end

  defp update_table_configuration(conn, table_configuration_id, settings) do
    query = """
    mutation {
      updateTableConfiguration(id: #{table_configuration_id}, settings: #{map_to_input_object_str(settings)}) {
        id
        title
        type
        isPublic
        description
        pageSize
        user{ id email }
        columns
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(query))
    |> json_response(200)
  end

  defp delete_table_configuration(conn, table_configuration_id) do
    query = """
    mutation {
      deleteTableConfiguration(id: #{table_configuration_id}) {
        id
        title
        type
        isPublic
        description
        pageSize
        user{ id email }
        columns
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(query))
    |> json_response(200)
  end

  defp get_table_configuration(conn, table_configuration_id) do
    query = """
    {
      tableConfiguration(id: #{table_configuration_id}) {
        id
        title
        type
        isPublic
        description
        pageSize
        user{ id email }
        columns
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp get_table_configurations(conn, nil) do
    query = """
    {
      tableConfigurations {
        id
        title
        type
        isPublic
        description
        pageSize
        user{ id email }
        columns
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp get_table_configurations(conn, user_id) do
    query = """
    {
      tableConfigurations(#{if user_id, do: "user_id: #{user_id}"}) {
        id
        title
        type
        isPublic
        description
        pageSize
        user{ id email }
        columns
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
