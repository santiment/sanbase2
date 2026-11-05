defmodule SanbaseWeb.Plug.AiReviewApiAuth do
  @moduledoc """
  Guards the AI review API (`/admin_api/ai_review`). The route is also served
  only from the admin pod (VPN), see `SanbaseWeb.Plug.AdminPodOnly`.

  Credentials: an API key (`Authorization: Apikey <key>`) or an OAuth bearer
  token. The user needs an Admin Panel role: any of them can read, Editor or
  Owner can also resolve and reopen issues (`conn.assigns.ai_review_can_write?`).
  """

  @behaviour Plug

  import Plug.Conn

  alias Sanbase.DiscordBot.AiReviewIssues

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with %Sanbase.Accounts.User{} = user <-
           Sanbase.MCP.Auth.headers_list_to_user(conn.req_headers),
         role_ids = role_ids(user),
         true <- AiReviewIssues.can_read?(role_ids) do
      conn
      |> assign(:current_user, user)
      |> assign(:ai_review_can_write?, AiReviewIssues.can_resolve?(role_ids))
    else
      nil -> reject(conn, 401, "Valid API key or OAuth token required")
      false -> reject(conn, 403, "An Admin Panel role is required")
    end
  end

  defp role_ids(user) do
    user
    |> Sanbase.Repo.preload([roles: :role], force: true)
    |> Map.get(:roles)
    |> Enum.map(& &1.role_id)
  end

  defp reject(conn, status, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: message}))
    |> halt()
  end
end
