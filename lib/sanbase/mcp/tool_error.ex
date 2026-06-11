defmodule Sanbase.MCP.ToolError do
  @moduledoc """
  Permanence tags for MCP tool errors, consumed by agent clients (e.g. the deep
  research agent) to decide how to proceed after a failed call.

  - `[permanent]` — the same arguments can never succeed (validation failures,
    unknown metric/slug names). Clients should fix the arguments (use the
    discovery tools) or move on; retrying is pointless.
  - `[transient]` — a later retry may succeed (upstream timeout, temporary
    unavailability).

  Untagged errors are classified heuristically on the client side — tag at the
  source whenever the permanence is actually known. Keep the message itself
  actionable: say what was wrong AND which tool resolves valid values.
  """

  @spec permanent(String.t()) :: String.t()
  def permanent(message) when is_binary(message), do: "[permanent] " <> message

  @spec transient(String.t()) :: String.t()
  def transient(message) when is_binary(message), do: "[transient] " <> message
end
