defmodule Sanbase.MCP.Knowledge.Access do
  @moduledoc """
  Only `@santiment.net` users with the Knowledge MCP User role may use the
  knowledge MCP. The role is checked on every request, so removing it revokes
  access even for tokens issued before.
  """

  alias Sanbase.Accounts.Role
  alias Sanbase.Accounts.User

  @domain "@santiment.net"

  @spec allowed?(User.t() | nil) :: boolean()
  def allowed?(user), do: allowed?(user, Role.mcp_knowledge_access_role_id())

  @doc "Whether the user is a team member, is not MCP-banned and has the role."
  @spec allowed?(User.t() | nil, non_neg_integer()) :: boolean()
  def allowed?(%User{is_mcp_banned: true}, _role_id), do: false

  def allowed?(%User{id: user_id, email: email}, role_id) when is_binary(email) do
    team_email?(email) and Role.user_has_role?(user_id, role_id)
  end

  def allowed?(_user, _role_id), do: false

  @spec team_email?(String.t() | nil) :: boolean()
  def team_email?(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
    |> String.ends_with?(@domain)
  end

  def team_email?(_), do: false

  @spec denied_message() :: String.t()
  def denied_message() do
    "The Santiment knowledge MCP is available only to Santiment team members " <>
      "with the Knowledge MCP User role. Ask an Admin Panel Owner to grant it."
  end
end
