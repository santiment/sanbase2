defmodule Sanbase.MCP.Dev.Access do
  @moduledoc """
  Only `@santiment.net` users with the Dev MCP User role may use the dev MCP.
  """

  alias Sanbase.Accounts.Role
  alias Sanbase.Accounts.User
  alias Sanbase.MCP.Knowledge

  @spec allowed?(User.t() | nil) :: boolean()
  def allowed?(user), do: Knowledge.Access.allowed?(user, Role.mcp_dev_access_role_id())

  @spec denied_message() :: String.t()
  def denied_message() do
    "The Santiment dev MCP is available only to Santiment team members " <>
      "with the Dev MCP User role. Ask an Admin Panel Owner to grant it."
  end
end
