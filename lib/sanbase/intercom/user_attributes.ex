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
    |> persist_sync()
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

  # helpers

  defp persist_sync({:ok, user_attributes} = result) do
    [user_attributes]
    |> to_json_kv_tuple()
    |> Sanbase.KafkaExporter.send_data_to_topic_from_current_process(@topic)

    result
  end

  defp persist_sync(result), do: result

  defp to_json_kv_tuple(user_attributes) do
    user_attributes
    |> Enum.map(fn %{user_id: user_id, properties: attributes, inserted_at: timestamp} ->
      timestamp = DateTime.to_unix(timestamp)
      key = "#{user_id}_#{timestamp}"

      data = %{
        user_id: user_id,
        attributes: attributes |> Map.delete("email") |> Map.delete("name") |> Jason.encode!(),
        timestamp: timestamp
      }

      {key, Jason.encode!(data)}
    end)
  end
end
