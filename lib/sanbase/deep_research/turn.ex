defmodule Sanbase.DeepResearch.Turn do
  @moduledoc """
  One question/answer exchange of a research transcript: the asked `question`,
  the ordered `timeline` of research items, accumulated `sources`, the final
  `report` (or `clarification` questions), timing, and the turn's `phase`.

  Built by `Sanbase.DeepResearch.Timeline.new_turn/3` and folded forward by
  `Timeline.apply_result/2`. The LiveView holds one current turn plus a list of
  finished ones; the components render straight off these fields.
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
    phase: :planning,
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
          error: String.t() | nil
        }
end
