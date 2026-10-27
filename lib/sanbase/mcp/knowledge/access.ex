defmodule Sanbase.MCP.Knowledge.Access do
  @moduledoc """
  Only `@santiment.net` users may use the knowledge MCP. Stricter than
  `Sanbase.MCP.ToolInvocation.team_member?/1` on purpose.
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
