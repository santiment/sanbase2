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
          optional(atom()) => term()
        }

  @spec mask_attrs(attrs(), boolean()) :: attrs()
  def mask_attrs(attrs, false), do: attrs

  def mask_attrs(attrs, true) do
    masked = Accounts.masked_sentinel()

    %{
      attrs
      | tool_name: masked,
        params: %{},
        error_message: if(attrs.error_message, do: masked, else: nil),
        user_agent: nil,
        client: nil
    }
  end
end
