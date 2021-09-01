defmodule SanbaseWeb.Graphql.WebinarsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  describe "get webinars" do
    setup do
      now = Timex.now()
      one_min_ago = Timex.shift(now, minutes: -1)
      free_webinar = insert(:webinar, is_pro: false, inserted_at: now)
      pro_webinar = insert(:webinar, is_pro: true, inserted_at: one_min_ago)

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
        free_webinar: free_webinar,
        pro_webinar: pro_webinar,
        free_conn: free_conn,
        basic_conn: basic_conn,
        pro_conn: pro_conn
      }
    end

    test "not logged in user - gets url only for non pro webinar", context do
      res = get_webinars(build_conn())

      assert Enum.map(res, & &1["title"]) == [
               context.free_webinar.title,
               context.pro_webinar.title
             ]

      assert Enum.map(res, & &1["url"]) == [context.free_webinar.url, nil]
    end

    test "logged in, free user - gets all fields for free webinars and preview fields for pro webinars",
         context do
      res = get_webinars(context.free_conn)

      assert Enum.map(res, & &1["title"]) == [
               context.free_webinar.title,
               context.pro_webinar.title
             ]

      assert Enum.map(res, & &1["url"]) == [context.free_webinar.url, nil]
    end

    test "with basic sanbase user gets all fields of free webinars and preview fields for pro webinars",
         context do
      res = get_webinars(context.basic_conn)

      assert Enum.map(res, & &1["title"]) == [
               context.free_webinar.title,
               context.pro_webinar.title
             ]

      assert Enum.map(res, & &1["url"]) == [context.free_webinar.url, nil]
    end

    test "with pro sanbase user list all published webinars", context do
      res = get_webinars(context.pro_conn)

      assert Enum.map(res, & &1["title"]) == [
               context.free_webinar.title,
               context.pro_webinar.title
             ]

      assert Enum.map(res, & &1["url"]) == [
               context.free_webinar.url,
               context.pro_webinar.url
             ]
    end
  end

  describe "Register for webinar" do
    test "successfull registration", context do
      free_webinar = insert(:webinar, is_pro: false)
      mutation = register_mutation(free_webinar.id)
      assert execute_mutation(context.conn, mutation, "registerForWebinar")

      registered_users = Sanbase.Webinars.Registration.list_users_in_webinar(free_webinar.id)
      assert context.user.id in Enum.map(registered_users, & &1.id)
    end

    test "register twice results in one record", context do
      free_webinar = insert(:webinar, is_pro: false)
      mutation = register_mutation(free_webinar.id)
      assert execute_mutation(context.conn, mutation, "registerForWebinar")
      assert execute_mutation(context.conn, mutation, "registerForWebinar")

      registered_users = Sanbase.Webinars.Registration.list_users_in_webinar(free_webinar.id)
      assert context.user.id in Enum.map(registered_users, & &1.id)
      assert Enum.count(registered_users, fn user -> user.id == context.user.id end) == 1
    end
  end

  defp get_webinars(conn) do
    query = """
    {
      getWebinars {
        url
        title
        description
        isPro
        startTime
        endTime
        imageUrl
        insertedAt
      }
    }
    """

    execute_query(conn, query, "getWebinars")
  end

  defp register_mutation(webinar_id) do
    """
    mutation {
      registerForWebinar(webinar_id: #{webinar_id})
    }
    """
  end
end
