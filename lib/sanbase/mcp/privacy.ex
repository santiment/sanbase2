defmodule Sanbase.MCP.Privacy do
  @moduledoc """
  Applies the privacy mask to `tool_invocations` attributes before they
  are persisted. The caller decides whether masking applies — usually by
  reading `activity_traces_hidden` off the per-request
  `Sanbase.RequestContext` struct — so the decision is made once at the
  edge and not re-queried here.

  When masking applies, the row is recorded with
  `Sanbase.Accounts.masked_sentinel/0` (`<activity_traces_hidden>`)
  placeholders so the existence and shape of activity (counts,
  durations, success flag) can still be measured without revealing what
  was queried or which client was used.
  """

  alias Sanbase.Accounts

  @type attrs :: %{
          required(:user_id) => non_neg_integer() | nil,
          required(:tool_name) => String.t(),
          required(:params) => map(),
          required(:error_message) => String.t() | nil,
          required(:user_agent) => String.t() | nil,
          required(:client) => String.t() | nil,
          # Required (not optional): `mask_attrs/2` nils these via the
          # `%{attrs | ...}` update syntax, which raises `KeyError` if the
          # key is absent. The sole builder (`MCP.Server.build_attrs/6`)
          # always sets them.
          required(:session_id) => String.t() | nil,
          required(:response_size_bytes) => non_neg_integer() | nil,
          optional(atom()) => term()
        }

  @doc """
  Masks `tool_invocations` attributes when the second argument is `true`
  (the caller's `activity_traces_hidden?` decision). When `false`, attrs
  pass through unchanged.

  Masked: `tool_name`/`params`/`user_agent`/`client`/`session_id` and a
  non-nil `error_message` (replaced with `Sanbase.Accounts.masked_sentinel/0`),
  plus `response_size_bytes` (a result-shape side channel). Kept:
  `user_id` (billing) and the shape metrics (counts, `duration_ms`,
  `is_successful`).

  ## Examples

      iex> attrs = %{user_id: 1, tool_name: "fetch_metric", params: %{slug: "bitcoin"}, error_message: nil, user_agent: "Claude", client: "cursor", session_id: "s1", response_size_bytes: 9}
      iex> Sanbase.MCP.Privacy.mask_attrs(attrs, false) == attrs
      true

      iex> attrs = %{user_id: 1, tool_name: "fetch_metric", params: %{slug: "bitcoin"}, error_message: nil, user_agent: "Claude", client: "cursor", session_id: "s1", response_size_bytes: 9}
      iex> masked = Sanbase.MCP.Privacy.mask_attrs(attrs, true)
      iex> masked.tool_name == Sanbase.Accounts.masked_sentinel()
      true
      iex> {masked.params, masked.session_id, masked.user_id}
      {%{}, nil, 1}
  """
  @spec mask_attrs(attrs(), boolean()) :: attrs()
  def mask_attrs(attrs, false), do: attrs

  def mask_attrs(attrs, true) do
    masked = Accounts.masked_sentinel()

    # session_id links separate invocations into one trace; response size
    # is a side-channel that can fingerprint a known query by its result
    # shape. Drop both. Counts/durations/success flag are kept on purpose.
    %{
      attrs
      | tool_name: masked,
        params: %{},
        error_message: if(attrs.error_message, do: masked, else: nil),
        user_agent: nil,
        client: nil,
        session_id: nil,
        response_size_bytes: nil
    }
  end
end
