defmodule SanbaseWeb.CustomAdminController do
  use SanbaseWeb, :controller

  @resources [
    :users,
    :subscriptions,
    :user_affiliate_details
  ]

  def index(conn, _params) do
    render(conn, :index,
      search_value: "",
      routes: resources_to_routes() ++ custom_routes()
    )
  end

  def custom_routes do
    [
      {"Webinars", ~p"/admin2/webinars"},
      {"Sheets templates", ~p"/admin2/sheets_templates/"},
      {"Reports", ~p"/admin2/reports"},
      {"Custom plans", ~p"/admin2/custom_plans"},
      {"Monitored Twitter Handles", ~p"/admin2/monitored_twitter_handle_live"}
    ]
  end

  def resources_to_routes do
    @resources
    |> Enum.map(fn resource ->
      str_name = Atom.to_string(resource)
      resource_name = String.capitalize(str_name)
      {resource_name, ~p"/admin2/generic?resource=#{str_name}"}
    end)
  end
end
