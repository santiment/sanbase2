defmodule SanbaseWeb.CustomAdminController do
  use SanbaseWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html",
      search_value: "",
      routes: [
        {"Users", ~p"/admin2/users"},
        {"Webinars", ~p"/admin2/webinars"},
        {"Sheets templates", ~p"/admin2/sheets_templates/"},
        {"Reports", ~p"/admin2/reports"},
        {"Custom plans", ~p"/admin2/custom_plans"},
        {"Monitored Twitter Handles", ~p"/admin2/monitored_twitter_handle_live"}
      ]
    )
  end
end
