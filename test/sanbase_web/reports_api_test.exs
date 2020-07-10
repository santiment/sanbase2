defmodule SanbaseWeb.Graphql.ReportsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)

    conn = setup_jwt_auth(build_conn(), user)
    basic_auth_conn = setup_basic_auth(conn, "user", "pass")

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

  describe "list all reports" do
    setup do
      not_published = insert(:report, is_published: false)
      free_report = insert(:report, is_pro: false, is_published: true)
      pro_report = insert(:report, is_pro: true, is_published: true)

      free_user = insert(:user)
      free_conn = setup_jwt_auth(build_conn(), free_user)

      pro_user = insert(:user)
      insert(:subscription_pro_sanbase, user: pro_user)
      pro_conn = setup_jwt_auth(build_conn(), pro_user)

      {
        :ok,
        not_published: not_published,
        free_report: free_report,
        pro_report: pro_report,
        free_conn: free_conn,
        pro_conn: pro_conn
      }
    end

    test "with free sanbase user, list only free published reports", context do
      res = get_reports(context.free_conn)

      assert Enum.map(res["data"]["getReports"], & &1["url"]) == [context.free_report.url]
    end

    test "with pro sanbase user list all published reports", context do
      res = get_reports(context.pro_conn)

      assert Enum.map(res["data"]["getReports"], & &1["url"]) == [
               context.free_report.url,
               context.pro_report.url
             ]
    end

    test "with user without auth returns unauthorized" do
      %{"errors" => [error]} = get_reports(build_conn())

      assert error["message"] =~ "unauthorized"
    end
  end

  def get_reports(conn) do
    query = """
    {
      getReports
      {
        url
        name
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
