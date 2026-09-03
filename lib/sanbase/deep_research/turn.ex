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
  can tell a busy agent from a stalled one) and `live` (what the model is producing
  right now — the tool call whose arguments it is still writing — which never becomes
  a timeline item because it is neither text nor a finished call).
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
          live: live() | nil
        }

  @typedoc "The model's in-progress output: a tool call whose arguments are still streaming."
  @type live :: %{
          kind: :tool_call_draft,
          name: String.t(),
          chars: non_neg_integer(),
          preview: String.t()
        }
end
