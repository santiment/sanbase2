defmodule Sanbase.DeepResearch.Event do
  @moduledoc """
  One parsed line of the agent's stream: what `Sanbase.DeepResearch.EventParser`
  produces and `Sanbase.DeepResearch.Timeline.apply_result/2` folds into a `Turn`.

  Every field is optional and one line can fill several (an `:activity` plus a
  `:phase`). All of them nil means "nothing to apply" — a heartbeat, stream noise, or
  a tool message; `empty?/1` says so, and `Client` drops those instead of forwarding
  them, so an empty event never reaches a turn.

    * `run_id`   - the run id, for cancellation. Comes with the `metadata` event a
                   worker emits when it picks the run up, so it arrives alongside a
                   `phase` (out of `:queued`) and a `run_started`/`run_restarted`
                   status activity.
    * `phase`    - phase hint
    * `report`   - final report markdown
    * `thinking` - cumulative AI snapshot for one message id
    * `live`     - what the model is producing right now (see `t:Turn.live/0`). Never
                   a timeline item: the UI shows it as "what the agent is doing now"
                   and drops it once the call lands.
    * `activity` - one event off the custom protocol channel: search/mcp/fetch calls
                   and their results, status rows, the plan, the run's usage ledger.
    * `error`    - terminal error detail: a `status: error`, a gateway `stream_error`,
                   or LangGraph's own `error` payload when a run crashes.
    * `meta`     - MCP gateway telemetry (`mcp_tool_calls`, `mcp_configured`,
                   `mcp_warning`)
    * `at`       - when the runner received the line, in ms. Stamped on receipt rather
                   than by the parser, so the UI can say how long the stream has been
                   silent.
  """

  alias Sanbase.DeepResearch.Turn

  defstruct [:run_id, :phase, :report, :thinking, :live, :activity, :error, :meta, :at]

  @typedoc "The phases a streamed line can imply. A turn has more (see `Timeline`)."
  @type phase :: :planning | :researching | :writing | :awaiting_user

  @type t :: %__MODULE__{
          run_id: String.t() | nil,
          phase: phase() | nil,
          report: String.t() | nil,
          thinking: %{id: String.t(), text: String.t()} | nil,
          live: Turn.live() | nil,
          activity: %{required(:kind) => atom(), optional(atom()) => term()} | nil,
          error: String.t() | nil,
          meta: %{optional(atom()) => term()} | nil,
          at: non_neg_integer() | nil
        }

  # `at` says nothing on its own, and is stamped after this check anyway.
  @payload_fields [:run_id, :phase, :report, :thinking, :live, :activity, :error, :meta]

  @doc "True when the line carried nothing to apply: a heartbeat, noise, or a tool message."
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{} = event),
    do: Enum.all?(@payload_fields, &is_nil(Map.fetch!(event, &1)))
end
