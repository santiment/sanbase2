defmodule Sanbase.GrafanaApi do
  require Sanbase.Utils.Config, as: Config
  require Mockery.Macro
  require Logger

  alias Sanbase.Auth.User

  @plan_team_map %{
    41 => "Sangraphs-Basic",
    42 => "Sangraphs-Pro"
  }

  def plan_team_map, do: @plan_team_map

  def add_subscribed_user_to_team(%User{} = user, plan_id) do
    team_name = @plan_team_map[plan_id]

    with {:ok, %{"id" => team_id}} <- get_team_by_name(team_name),
         {:ok, %{"id" => user_id}} <- get_user_by_email_or_metamask(user),
         {:ok, team_members} <- get_team_members(team_id) do
      team_members
      |> Enum.find(fn %{"userId" => uid} -> uid == user_id end)
      |> case do
        nil -> add_user_to_team(user_id, team_id)
        _ -> {:ok, "User is already in this team"}
      end
    else
      error -> error
    end
  end

  # helpers

  defp get_team_by_name(name) do
    request_path = "api/teams/search?name=#{name}"

    http_client().get(base_url() <> request_path, headers())
    |> handle_response()
    |> case do
      {:ok, teams} ->
        {:ok, Map.get(teams, "teams") |> hd()}

      {:error, error} ->
        {:error, error}
    end
  end

  defp get_team_members(team_id) do
    request_path = "api/teams/#{team_id}/members"

    http_client().get(base_url() <> request_path, headers())
    |> handle_response()
  end

  defp add_user_to_team(user_id, team_id) do
    request_path = "api/teams/#{team_id}/members"
    data = %{"userId" => user_id} |> Jason.encode!()

    http_client().post(base_url() <> request_path, data, headers())
    |> handle_response()
  end

  defp get_user_by_email_or_metamask(%User{username: username, email: email}) do
    token = email || username
    request_path = "api/users/lookup?loginOrEmail=#{token}"

    http_client().get(base_url() <> request_path, headers())
    |> handle_response()
  end

  defp http_client(), do: HTTPoison

  defp base_url, do: Config.get(:grafana_base_url)

  defp basic_auth_header() do
    credentials =
      (Config.get(:grafana_user) <> ":" <> Config.get(:grafana_pass))
      |> Base.encode64()

    {"Authorization", "Basic #{credentials}"}
  end

  defp headers() do
    [
      {"Content-Type", "application/json"},
      basic_auth_header()
    ]
  end

  defp handle_response(response) do
    response
    |> case do
      {:ok, %HTTPoison.Response{status_code: code, body: body}} when code in 200..299 ->
        {:ok, body |> Jason.decode!()}

      other ->
        Logger.error("Error response from grafana API: #{inspect(other)}")
        {:error, "Error response from grafana API"}
    end
  end
end
