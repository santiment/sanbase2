defmodule Sanbase.MCP.Knowledge.Access do
  @moduledoc """
  Who may use the knowledge MCP served at `/mcp_knowledge`: Santiment team
  members, identified by an `@santiment.net` email.

  This is deliberately stricter than `Sanbase.MCP.ToolInvocation.team_member?/1`,
  which also matches superusers and configured personal addresses. The check
  is only as strong as email verification at login: every login path sets the
  email from a verified source (magic link, Google, Twitter).
  """

  alias Sanbase.Accounts.User

  @domain "@santiment.net"

  @spec allowed?(User.t() | nil) :: boolean()
  def allowed?(%User{email: email}) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
    |> String.ends_with?(@domain)
  end

  def allowed?(_), do: false

  @spec denied_message() :: String.t()
  def denied_message() do
    "The Santiment knowledge MCP is available only to Santiment team members " <>
      "(#{@domain} accounts). Log in with your #{@domain} Sanbase account."
  end
end
