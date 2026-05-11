defmodule Sanbase.MajorTopics.TopicBatch do
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Accounts.User
  alias Sanbase.MajorTopics.MajorTopic

  @draft "draft"
  @published "published"
  @states [@draft, @published]

  def draft_state, do: @draft
  def published_state, do: @published
  def states, do: @states

  schema "topic_batches" do
    field(:source, :string)
    field(:interval_text, :string)
    field(:interval_start, :date)
    field(:interval_end, :date)
    field(:version, :integer, default: 1)
    field(:type, :string)
    field(:state, :string, default: @draft)
    field(:published_at, :utc_datetime)
    field(:fetched_at, :utc_datetime)

    belongs_to(:published_by, User)
    has_many(:topics, MajorTopic, foreign_key: :batch_id, on_delete: :delete_all)

    timestamps()
  end

  def changeset(batch, attrs) do
    batch
    |> cast(attrs, [
      :source,
      :interval_text,
      :interval_start,
      :interval_end,
      :version,
      :type,
      :state,
      :published_at,
      :published_by_id,
      :fetched_at
    ])
    |> validate_required([
      :source,
      :interval_text,
      :interval_start,
      :interval_end,
      :version,
      :state,
      :fetched_at
    ])
    |> validate_inclusion(:state, @states)
    |> unique_constraint([:source, :interval_text, :version])
  end

  def publish_changeset(batch, user_id, now \\ DateTime.utc_now()) do
    batch
    |> cast(
      %{
        state: @published,
        published_at: DateTime.truncate(now, :second),
        published_by_id: user_id
      },
      [:state, :published_at, :published_by_id]
    )
    |> validate_inclusion(:state, @states)
  end
end
