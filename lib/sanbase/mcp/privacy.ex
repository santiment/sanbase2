defmodule Sanbase.MCP.Privacy do
  @moduledoc """
  Applies the privacy mask to `tool_invocations` attributes before they are
  persisted. For users in `Sanbase.Accounts.activity_traces_hidden_user_ids/0`
  the call is recorded with `<masked>` placeholders so the existence and
  shape of activity (counts, durations, success flag) can still be measured
  without revealing what was queried or which client was used.

  Kept separate from `Sanbase.MCP.Server` so the masking decision can be
  unit-tested without spinning up an MCP frame.
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

  @spec mask_attrs(attrs()) :: attrs()
  def mask_attrs(%{user_id: user_id} = attrs) do
    if Accounts.activity_traces_hidden?(user_id) do
      masked = Accounts.masked_sentinel()

      %{
        attrs
        | tool_name: masked,
          params: %{},
          error_message: if(attrs.error_message, do: masked, else: nil),
          user_agent: nil,
          client: nil
      }
    else
      attrs
    end
  end
end
