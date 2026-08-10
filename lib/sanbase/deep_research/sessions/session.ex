defmodule Sanbase.DeepResearch.Sessions.Session do
  @moduledoc """
  A persisted deep research conversation: who ran it, when, with what model
  tier, and whether it is shared.

  The UUID primary key doubles as the share-link identifier — revoking a share
  is flipping `is_public` back to false, not rotating the link.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Accounts.User

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          title: String.t(),
          model_tier: String.t(),
          thread_id: String.t() | nil,
          is_public: boolean(),
          user_id: integer(),
          user: User.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "deep_research_sessions" do
    field(:title, :string)
    field(:model_tier, :string)
    field(:thread_id, :string)
    field(:is_public, :boolean, default: false)

    belongs_to(:user, User, type: :integer)

    timestamps()
  end

  @required_fields [:title, :model_tier, :user_id]
  @optional_fields [:thread_id, :is_public]

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = session, attrs \\ %{}) do
    session
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:title, min: 1, max: 255)
    |> foreign_key_constraint(:user_id)
  end
end
