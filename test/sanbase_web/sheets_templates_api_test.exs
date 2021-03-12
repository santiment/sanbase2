defmodule SanbaseWeb.Graphql.SheetsTemplatesApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn}
  end

  describe "get sheets templates" do
    setup do
      free_template = insert(:sheets_template, is_pro: false)
      pro_template = insert(:sheets_template, is_pro: true)

      free_user = insert(:user)
      free_conn = setup_jwt_auth(build_conn(), free_user)

      pro_user = insert(:user)
      basic_user = insert(:user)
      insert(:subscription_pro_sanbase, user: pro_user)
      insert(:subscription_basic_sanbase, user: basic_user)
      pro_conn = setup_jwt_auth(build_conn(), pro_user)
      basic_conn = setup_jwt_auth(build_conn(), basic_user)

      {
        :ok,
        free_template: free_template,
        pro_template: pro_template,
        free_conn: free_conn,
        basic_conn: basic_conn,
        pro_conn: pro_conn
      }
    end

    test "not logged in user - gets only preview fields", context do
      res = get_sheets_templates(build_conn())

      assert Enum.map(res, & &1["name"]) == [
               context.free_template.name,
               context.pro_template.name
             ]

      assert Enum.map(res, & &1["url"]) == [nil, nil]
    end

    test "logged in, free user - gets all fields for free templates and preview fields for pro templates",
         context do
      res = get_sheets_templates(context.free_conn)

      assert Enum.map(res, & &1["name"]) == [
               context.free_template.name,
               context.pro_template.name
             ]

      assert Enum.map(res, & &1["url"]) == [context.free_template.url, nil]
    end

    test "with basic sanbase user list all published templates", context do
      res = get_sheets_templates(context.basic_conn)

      assert Enum.map(res, & &1["name"]) == [
               context.free_template.name,
               context.pro_template.name
             ]

      assert Enum.map(res, & &1["url"]) == [
               context.free_template.url,
               context.pro_template.url
             ]
    end

    test "with pro sanbase user list all published templates", context do
      res = get_sheets_templates(context.pro_conn)

      assert Enum.map(res, & &1["name"]) == [
               context.free_template.name,
               context.pro_template.name
             ]

      assert Enum.map(res, & &1["url"]) == [
               context.free_template.url,
               context.pro_template.url
             ]
    end
  end

  def get_sheets_templates(conn) do
    query = """
    {
      getSheetsTemplates {
        url
        name
        description
        isPro
      }
    }
    """

    execute_query(conn, query, "getSheetsTemplates")
  end
end
