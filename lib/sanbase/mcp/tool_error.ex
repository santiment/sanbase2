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

  @doc """
  Tag a message as a permanent tool error — the same arguments can never
  succeed, so the client should fix them or move on rather than retry.

  ## Examples

      iex> Sanbase.MCP.ToolError.permanent("Unknown metric 'pric_usd'")
      "[permanent] Unknown metric 'pric_usd'"
  """
  @spec permanent(String.t()) :: String.t()
  def permanent(message) when is_binary(message), do: "[permanent] " <> message

  @doc """
  Tag a message as a transient tool error — a later retry with the same
  arguments may succeed (upstream timeout, temporary unavailability).

  ## Examples

      iex> Sanbase.MCP.ToolError.transient("Upstream request timed out")
      "[transient] Upstream request timed out"
  """
  @spec transient(String.t()) :: String.t()
  def transient(message) when is_binary(message), do: "[transient] " <> message

  @doc """
  Tag a message by its permanence. `:unknown` leaves it untagged, for the client to
  classify.

  ## Examples

      iex> Sanbase.MCP.ToolError.tag(:transient, "Upstream request timed out")
      "[transient] Upstream request timed out"

      iex> Sanbase.MCP.ToolError.tag(:unknown, "Upstream error")
      "Upstream error"
  """
  @spec tag(:permanent | :transient | :unknown, String.t()) :: String.t()
  def tag(:permanent, message), do: permanent(message)
  def tag(:transient, message), do: transient(message)
  def tag(:unknown, message) when is_binary(message), do: message
end
