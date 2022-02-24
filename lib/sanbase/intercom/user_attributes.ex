defmodule Sanbase.Intercom.UserAttributes do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo

  @topic "sanbase_user_intercom_attributes"

  schema "user_intercom_attributes" do
    field(:properties, :map)

    belongs_to(:user, Sanbase.Accounts.User)
    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user_attributes, attrs) do
    user_attributes
    |> cast(attrs, [:user_id, :properties])
    |> validate_required([:user_id, :properties])
  end

  def save(params) do
    %__MODULE__{}
    |> changeset(params)
    |> Repo.insert()
  end

  def get_attributes_for_users(user_ids, from, to) do
    from(ua in __MODULE__,
      where:
        ua.user_id in ^user_ids and
          ua.inserted_at >= ^from and
          ua.inserted_at <= ^to
    )
    |> Repo.all()
  end

  def persist_kafka_sync(user_attributes) do
    [user_attributes]
    |> to_json_kv_tuple()
    |> Sanbase.KafkaExporter.send_data_to_topic_from_current_process(@topic)
  end

  # helpers

  defp to_json_kv_tuple(user_attributes) do
    user_attributes
    |> Enum.map(fn %{user_id: user_id, properties: attributes, inserted_at: timestamp} ->
      timestamp = DateTime.to_unix(timestamp)
      key = "#{user_id}_#{timestamp}"

      data = %{
        user_id: user_id,
        attributes: Map.drop(attributes, ["email", "name", "phone", "avatar"]) |> Jason.encode!(),
        timestamp: timestamp
      }

      {key, Jason.encode!(data)}
    end)
  end
end
