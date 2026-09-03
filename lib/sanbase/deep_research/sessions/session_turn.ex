defmodule Sanbase.DeepResearch.Sessions.SessionTurn do
  @moduledoc """
  One persisted question/answer exchange of a deep research session — the row
  form of the in-memory `Sanbase.DeepResearch.Turn` struct (hence the distinct
  name). `Sanbase.DeepResearch.Sessions.TurnCodec` converts between the two.

  `timeline` and `sources` are stored as jsonb and load back string-keyed; only
  the codec knows how to rebuild the atom-keyed item maps the components render.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.DeepResearch.Sessions.Session
  alias Sanbase.DeepResearch.Timeline

  @phases Timeline.all_phases()

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          session_id: Ecto.UUID.t(),
          position: integer(),
          question: String.t(),
          report: String.t() | nil,
          error: String.t() | nil,
          clarification: [String.t()],
          phase: atom(),
          model_tier: String.t() | nil,
          timeline: [map()],
          sources: [map()],
          started_at: DateTime.t(),
          finished_at: DateTime.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "deep_research_turns" do
    field(:position, :integer)
    field(:question, :string)
    field(:report, :string)
    field(:error, :string)
    field(:clarification, {:array, :string}, default: [])
    field(:phase, Ecto.Enum, values: @phases, default: :queued)
    field(:model_tier, :string)
    field(:timeline, {:array, :map}, default: [])
    field(:sources, {:array, :map}, default: [])
    field(:started_at, :utc_datetime_usec)
    field(:finished_at, :utc_datetime_usec)

    belongs_to(:session, Session)

    timestamps()
  end

  @required_fields [:session_id, :position, :question, :started_at]
  @optional_fields [
    :report,
    :error,
    :clarification,
    :phase,
    :model_tier,
    :timeline,
    :sources,
    :finished_at
  ]

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = turn, attrs \\ %{}) do
    turn
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:session_id)
    |> unique_constraint([:session_id, :position])
  end
end
