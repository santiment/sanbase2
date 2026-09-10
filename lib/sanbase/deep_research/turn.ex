defmodule Sanbase.DeepResearch.Turn do
  @moduledoc """
  One question/answer exchange of a research transcript: the asked `question`,
  the ordered `timeline` of research items, accumulated `sources`, the final
  `report` (or `clarification` questions), timing, and the turn's `phase`.

  Built by `Sanbase.DeepResearch.Timeline.new_turn/3` and folded forward by
  `Timeline.apply_result/2`. The LiveView holds one current turn plus a list of
  finished ones; the components render straight off these fields.

  Two fields describe the stream itself rather than the research, and are not
  persisted: `last_event_at` (when the run last delivered anything at all, so the UI
  can tell a busy agent from a stalled one) and `live` (what the model is doing right
  now — writing a tool call's arguments, or running a model call that streams nothing
  — which never becomes a timeline item because it is neither text nor a finished call).
  """

  @enforce_keys [:id, :question, :started_at]
  defstruct [
    :id,
    :question,
    :report,
    :clarification,
    :started_at,
    :finished_at,
    :error,
    :last_event_at,
    :live,
    :usage,
    phase: :queued,
    timeline: [],
    sources: []
  ]

  @type t :: %__MODULE__{
          id: term(),
          question: String.t(),
          phase: Sanbase.DeepResearch.Timeline.phase(),
          timeline: [map()],
          sources: [map()],
          report: String.t() | nil,
          clarification: [String.t()] | nil,
          started_at: non_neg_integer(),
          finished_at: non_neg_integer() | nil,
          error: String.t() | nil,
          last_event_at: non_neg_integer() | nil,
          live: live() | nil,
          usage: usage() | nil
        }

  @typedoc """
  The agent's own ledger for the run, reported once as it ends. Every field is
  optional — the agent only reports what it measured. `total_tokens` is fleet-wide
  (orchestrator plus sub-agents) when the agent reports one.
  """
  @type usage :: %{
          optional(:elapsed_s) => number(),
          optional(:tool_calls) => non_neg_integer(),
          optional(:model_calls) => non_neg_integer(),
          optional(:total_tokens) => non_neg_integer(),
          optional(:cost_usd) => number(),
          optional(:subagent_runs) => non_neg_integer()
        }

  @typedoc """
  What the model is doing right now: writing a tool call's arguments (`:tool_call_draft`,
  with the plan so far when that call is `write_todos`), or waiting on a model call that
  streams nothing (`:model_call`).
  """
  @type live ::
          %{
            :kind => :tool_call_draft,
            :name => String.t(),
            :chars => non_neg_integer(),
            :preview => String.t(),
            optional(:todos) => [%{content: String.t(), status: String.t()}]
          }
          | %{
              kind: :model_call,
              role: String.t(),
              model: String.t() | nil,
              step: non_neg_integer() | nil,
              unit: String.t() | nil,
              after: String.t() | nil,
              after_chars: non_neg_integer() | nil
            }
end
