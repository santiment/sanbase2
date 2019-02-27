defmodule Sanbase.Signals.HistoricalActivity do
  @moduledoc ~s"""
  Table that persists triggered signals and their payload.
  """
  @derive [Jason.Encoder]

  use Ecto.Schema
  import Ecto.Query

  import Ecto.Changeset
  alias Sanbase.Signals.UserTrigger
  alias Sanbase.Auth.User
  alias Sanbase.Repo

  alias __MODULE__

  schema "signals_historical_activity" do
    belongs_to(:user, User)
    belongs_to(:user_trigger, UserTrigger)
    field(:payload, :map)

    timestamps()
  end

  def changeset(%HistoricalActivity{} = user_signal, attrs \\ %{}) do
    user_signal
    |> cast(attrs, [:user_id, :user_trigger_id, :payload])
    |> validate_required([:user_id, :user_trigger_id, :payload])
  end

  @doc """
  Fetch signal historical activity for user with before and after cursors ordered by inserted_at descending
  * `before` cursor is pointed at the last record of the return list. 
    It used for fetching messages `before` certain timestamp
  * `after` cursor is pointed at newest message. It is used for fetching the latest signal activity
  """

  def signals_historical_activity(
        %User{id: user_id} = user,
        %{limit: limit, before: before_datetime} = args
      ) do
    activity =
      HistoricalActivity
      |> user_historical_activity(user_id, limit)
      |> before_datetime(before_datetime)
      |> Repo.all()

    {before_datetime, after_datetime} = get_cursors(activity)

    {:ok, %{activity: activity, before: before_datetime, after: after_datetime}}
  end

  def signals_historical_activity(
        %User{id: user_id} = user,
        %{limit: limit, after: after_datetime} = args
      ) do
    activity =
      HistoricalActivity
      |> user_historical_activity(user_id, limit)
      |> after_datetime(after_datetime)
      |> Repo.all()

    {new_before_datetime, new_before_datetime} = get_cursors(activity)

    {:ok, %{activity: activity, before: new_before_datetime, after: new_before_datetime}}
  end

  def signals_historical_activity(%User{id: user_id} = user, %{limit: limit} = args) do
    activity =
      HistoricalActivity
      |> user_historical_activity(user_id, limit)
      |> Repo.all()

    {before_datetime, after_datetime} = get_cursors(activity)

    {:ok, %{activity: activity, before: before_datetime, after: after_datetime}}
  end

  def signals_historical_activity(_, args), do: {:error, "Wrong arguments!"}

  # private functions

  defp user_historical_activity(query, user_id, limit) do
    from(
      ha in query,
      where: ha.user_id == ^user_id,
      order_by: [desc: ha.inserted_at],
      limit: ^limit,
      preload: :user_trigger
    )
  end

  defp before_datetime(query, before_datetime) do
    from(
      ha in query,
      where: ha.inserted_at < ^before_datetime
    )
  end

  defp after_datetime(query, after_datetime) do
    from(
      ha in query,
      where: ha.inserted_at > ^after_datetime
    )
  end

  defp get_cursors(activity) do
    before_datetime = activity |> List.last() |> Map.get(:inserted_at)
    after_datetime = activity |> List.first() |> Map.get(:inserted_at)
    {before_datetime, after_datetime}
  end
end
