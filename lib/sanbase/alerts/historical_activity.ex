defmodule Sanbase.Alert.HistoricalActivity do
  @moduledoc ~s"""
  Table that persists triggered alerts and their payload.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias __MODULE__
  alias Sanbase.Accounts.User
  alias Sanbase.Alert.UserTrigger
  alias Sanbase.Repo

  @derive [Jason.Encoder]

  schema "signals_historical_activity" do
    field(:payload, :map)
    field(:data, :map)
    field(:triggered_at, :naive_datetime)

    belongs_to(:user, User)
    belongs_to(:user_trigger, UserTrigger)
  end

  def changeset(%HistoricalActivity{} = ha, attrs \\ %{}) do
    ha
    |> cast(attrs, [:user_id, :user_trigger_id, :payload, :data, :triggered_at])
    |> validate_required([:user_id, :user_trigger_id, :payload, :triggered_at])
  end

  def create(attrs) do
    %HistoricalActivity{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Fetch alert historical activity for user with cursor ordered by triggered_at
  descending. Cursor is a map with `type` (one of `:before` and `:after`) and
  `datetime`.
  * `before` cursor is pointed at the last record of the return list. It is used
    for fetching messages `before` certain datetime
  * `after` cursor is pointed at latest message. It is used for fetching the
    latest alert activity.
  """

  def fetch_historical_activity_for(%User{id: user_id}, %{
        limit: limit,
        cursor: %{type: cursor_type, datetime: cursor_datetime}
      }) do
    HistoricalActivity
    |> user_historical_activity(user_id, limit)
    |> by_cursor(cursor_type, cursor_datetime)
    |> Repo.all()
    |> activity_with_cursor()
  end

  def fetch_historical_activity_for(%User{id: user_id}, %{limit: limit}) do
    HistoricalActivity
    |> user_historical_activity(user_id, limit)
    |> Repo.all()
    |> activity_with_cursor()
  end

  def fetch_historical_activity_for(_, _), do: {:error, "Bad arguments"}

  # private functions

  defp user_historical_activity(query, user_id, limit) do
    san_family_ids = Sanbase.Accounts.Role.san_family_ids()

    from(
      ha in query,
      join: ut in UserTrigger,
      on: ha.user_trigger_id == ut.id,
      where:
        ha.user_id == ^user_id or
          (ha.user_id in ^san_family_ids and fragment("trigger->>'is_public' = 'true'")),
      order_by: [desc: ha.triggered_at],
      limit: ^limit,
      preload: :user_trigger
    )
  end

  defp by_cursor(query, :before, datetime) do
    from(
      ha in query,
      where: ha.triggered_at < ^datetime
    )
  end

  defp by_cursor(query, :after, datetime) do
    from(
      ha in query,
      where: ha.triggered_at > ^datetime
    )
  end

  defp activity_with_cursor([]), do: {:ok, %{activity: [], cursor: %{}}}

  defp activity_with_cursor(activity) do
    before_datetime = activity |> List.last() |> Map.get(:triggered_at)
    after_datetime = activity |> List.first() |> Map.get(:triggered_at)

    {:ok,
     %{
       activity: convert_activity_datetimes(activity),
       cursor: %{
         before: DateTime.from_naive!(before_datetime, "Etc/UTC"),
         after: DateTime.from_naive!(after_datetime, "Etc/UTC")
       }
     }}
  end

  defp convert_activity_datetimes(activity) do
    Enum.map(activity, fn %HistoricalActivity{triggered_at: triggered_at} = ha ->
      %{ha | triggered_at: DateTime.from_naive!(triggered_at, "Etc/UTC")}
    end)
  end
end
