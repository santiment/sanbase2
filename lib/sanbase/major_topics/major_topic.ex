defmodule Sanbase.MajorTopics.MajorTopic do
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.MajorTopics.TopicBatch

  schema "major_topics" do
    field(:ch_id, :string)
    field(:topic_id, :integer)
    field(:label, :string)
    field(:original_label, :string)
    field(:top_words, :string)
    field(:description, :string, default: "")
    field(:is_crypto_relevant, :boolean, default: true)
    field(:is_removed, :boolean, default: false)
    field(:position, :integer, default: 0)
    field(:values, {:array, :map}, default: [])

    belongs_to(:batch, TopicBatch)

    timestamps()
  end

  def changeset(topic, attrs) do
    topic
    |> cast(attrs, [
      :batch_id,
      :ch_id,
      :topic_id,
      :label,
      :original_label,
      :top_words,
      :description,
      :is_crypto_relevant,
      :is_removed,
      :position,
      :values
    ])
    |> validate_required([
      :batch_id,
      :ch_id,
      :topic_id,
      :label,
      :original_label,
      :top_words
    ])
    |> unique_constraint([:batch_id, :ch_id])
  end

  def moderation_changeset(topic, attrs) do
    topic
    |> cast(attrs, [:label, :is_removed])
    |> validate_required([:label])
    |> validate_length(:label, min: 1, max: 500)
  end
end
