defmodule SanbaseWeb.Graphql.ReportsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)

    conn = setup_jwt_auth(build_conn(), user)
    basic_auth_conn = setup_basic_auth(build_conn(), "user", "pass")

    {:ok, conn: conn, basic_auth_conn: basic_auth_conn}
  end

  describe "upload a report" do
    test "succeeds with basic auth", context do
      res = upload_report(context.basic_auth_conn)
      assert res["data"]["uploadReport"]["url"] =~ "image.png"
    end

    test "unauthorized with no auth" do
      %{"errors" => [error]} = upload_report(build_conn())
      assert error["message"] =~ "unauthorized"
    end

    test "unauthorized for jwt auth", context do
      %{"errors" => [error]} = upload_report(context.conn)
      assert error["message"] =~ "unauthorized"
    end
  end

  describe "get reports" do
    setup do
      not_published = insert(:report, is_published: false)
      free_report = insert(:report, is_pro: false, is_published: true)
      pro_report = insert(:report, is_pro: true, is_published: true)

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
        not_published: not_published,
        free_report: free_report,
        pro_report: pro_report,
        free_conn: free_conn,
        basic_conn: basic_conn,
        pro_conn: pro_conn
      }
    end

    test "not logged in user - gets only report preview fields", context do
      res = get_reports(build_conn())

      assert Enum.map(res["data"]["getReports"], & &1["name"]) == [
               context.free_report.name,
               context.pro_report.name
             ]

      assert Enum.map(res["data"]["getReports"], & &1["url"]) == [nil, nil]
    end

    test "logged in, free user - gets all fields for free reports and preview fields for pro reports",
         context do
      res = get_reports(context.free_conn)

      assert Enum.map(res["data"]["getReports"], & &1["name"]) == [
               context.free_report.name,
               context.pro_report.name
             ]

      assert Enum.map(res["data"]["getReports"], & &1["url"]) == [context.free_report.url, nil]
    end

    test "with basic sanbase user list all published reports", context do
      res = get_reports(context.basic_conn)

      assert Enum.map(res["data"]["getReports"], & &1["name"]) == [
               context.free_report.name,
               context.pro_report.name
             ]

      assert Enum.map(res["data"]["getReports"], & &1["url"]) == [
               context.free_report.url,
               context.pro_report.url
             ]
    end

    test "with pro sanbase user list all published reports", context do
      res = get_reports(context.pro_conn)

      assert Enum.map(res["data"]["getReports"], & &1["name"]) == [
               context.free_report.name,
               context.pro_report.name
             ]

      assert Enum.map(res["data"]["getReports"], & &1["url"]) == [
               context.free_report.url,
               context.pro_report.url
             ]
    end
  end

  describe "get reports by tags" do
    setup do
      insert(:report, is_pro: false, is_published: true)
      r1 = insert(:report, is_pro: false, is_published: true, tags: ~w(t1 t2))
      r2 = insert(:report, is_pro: false, is_published: true, tags: ~w(t3 t4))
      insert(:report, is_pro: false, is_published: true, tags: ~w(t5 t6))

      user = insert(:user)
      conn = setup_jwt_auth(build_conn(), user)

      {:ok, conn: conn, r1: r1, r2: r2}
    end

    test "fetch only reports with intersecting tags", context do
      get_reports(context.conn)
      res = get_reports_by_tags(context.conn, ["t2", "t3"])

      assert Enum.map(res["data"]["getReportsByTags"], & &1["url"]) == [
               context.r1.url,
               context.r2.url
             ]
    end
  end

  def get_reports(conn) do
    query = """
    {
      getReports
      {
        url
        name
        description
        isPro
        tags
        insertedAt
      }
    }
    """

    conn
    |> post("/graphql", %{"query" => query})
    |> json_response(200)
  end

  def get_reports_by_tags(conn, tags) do
    query = """
    {
      getReportsByTags(tags: #{tags |> Jason.encode!()})
      {
        url
        name
        tags
        insertedAt
      }
    }
    """

    conn
    |> post("/graphql", %{"query" => query})
    |> json_response(200)
  end

  @test_file_path "#{File.cwd!()}/test/sanbase_web/graphql/assets/image.png"
  defp upload_report(conn) do
    mutation = """
      mutation {
        uploadReport(report: "report", name: "New Alpha Report") {
          name
          url
        }
      }
    """

    upload = %Plug.Upload{
      content_type: "application/octet-stream",
      filename: "image.png",
      path: @test_file_path
    }

    conn
    |> post("/graphql", %{"query" => mutation, "report" => upload})
    |> json_response(200)
  end
end
