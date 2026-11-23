defmodule Sanbase.MCP.Dev.Access do
  @moduledoc """
  Who may use the dev MCP: the same `@santiment.net` rule as the knowledge MCP.
  """

  alias Sanbase.Accounts.User
  alias Sanbase.MCP.Knowledge

  @spec allowed?(User.t() | nil) :: boolean()
  defdelegate allowed?(user), to: Knowledge.Access

  @spec denied_message() :: String.t()
  def denied_message() do
    "The Santiment dev MCP is available only to Santiment team members " <>
      "(@santiment.net accounts). Log in with your @santiment.net Sanbase account."
  end
end
