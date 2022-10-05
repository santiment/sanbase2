defmodule SanbaseWeb.CustomAdminController do
  use SanbaseWeb, :controller

  alias SanbaseWeb.Router.Helpers, as: Routes

  def index(conn, _params) do
    render(conn, "index.html",
      search_value: "",
      routes: [
        {"Users", Routes.user_path(conn, :index)},
        {"Webinars", Routes.webinar_path(conn, :index)},
        {"Sheets templates", Routes.sheets_template_path(conn, :index)},
        {"Reports", Routes.report_path(conn, :index)},
        {"Custom plans", Routes.custom_plan_path(conn, :index)}
      ]
    )
  end
end
