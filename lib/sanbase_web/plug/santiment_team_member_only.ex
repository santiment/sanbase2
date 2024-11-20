defmodule SanbaseWeb.Plug.SantimentTeamMemberOnly do
  @moduledoc ~s"""
  Check if the container type allows access to the admin dashboard
  endpoints. T
  """

  @behaviour Plug

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _) do
    case get_in(conn.private, [:san_authentication, :auth, :current_user]) do
      %Sanbase.Accounts.User{} = user ->
        if santiment_member?(user) do
          conn
        else
          conn
          |> send_resp(403, "Unauthorized")
          |> halt()
        end

      _ ->
        conn
        |> send_resp(403, "Unauthorized")
        |> halt()
    end
  end

  defp santiment_member?(%Sanbase.Accounts.User{} = user) do
    cond do
      has_san_team_role?(user) -> true
      is_binary(user.email) and String.ends_with?(user.email, "@santiment.net") -> true
      true -> false
    end
  end

  defp has_san_team_role?(user) do
    user = Sanbase.Repo.preload(user, [:roles, roles: :role])
    Enum.any?(user.roles, &(&1.role.name in ["Santiment Team Member"]))
  end
end
