defmodule Sanbase.Intercom.UserAttributes do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo

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
end

defmodule Sanbase.Intercom.UserAttributes.KafkaDump do
  import Ecto.Query
  alias Sanbase.Intercom.UserAttributes
  alias Sanbase.Repo

  @topic "sanbase_user_intercom_attributes"

  def run_async() do
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      run()
    end)
  end

  def run() do
    query =
      from(ua in UserAttributes,
        select: %{user_id: ua.user_id, attributes: ua.properties, timestamp: ua.inserted_at}
      )

    stream = Repo.stream(query, timeout: :infinity)

    Repo.transaction(
      fn ->
        stream
        |> Enum.each(fn %{user_id: user_id, attributes: attributes, timestamp: timestamp} ->
          timestamp = DateTime.to_unix(timestamp)
          key = "#{user_id}_#{timestamp}" |> IO.inspect()

          data = %{
            user_id: user_id,
            attributes:
              attributes |> Map.delete("email") |> Map.delete("name") |> Jason.encode!(),
            timestamp: timestamp
          }

          SanExporterEx.Producer.send_data(@topic, [{key, Jason.encode!(data)}])
        end)
      end,
      timeout: :infinity
    )
  end
end
