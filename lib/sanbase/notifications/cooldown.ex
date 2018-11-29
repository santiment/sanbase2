defmodule Sanbase.Notifications.Cooldown do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias __MODULE__
  alias Sanbase.Repo

  @table "signal-cooldowns"

  schema @table do
    field(:signal, :string)
    field(:who_triggered, :string)
    field(:last_triggered, :naive_datetime)
  end

  def changeset(%Cooldown{} = cd, attrs \\ %{}) do
    cd
    |> cast(attrs, [:signal, :who_triggered, :last_triggered])
    |> validate_required([:signal, :who_triggered])
  end

  @doc ~s"""
  Return whether a given notification type has been sent for a project
  in the past `duration` seconds
  """
  @spec has_cooldown?(String.t(), String.t(), non_neg_integer(), Atom.t()) :: boolean()
  def has_cooldown?(signal, who, duration) do
    {has_cooldown?, _} = get_cooldown(signal, who, duration, duration_format)
    has_cooldown?
  end

  @doc ~s"""
  Return a tuple where the first argument shows whether a given notification type
  has been sent for a project in the past `duration` seconds.
  If there is a notification sent in the past `duration` seconds, the second argument
  is the datetime that it was sent.
  """
  @spec get_cooldown(String.t(), String.t(), non_neg_integer(), Atom.t()) ::
          {false, nil} | {true, %DateTime{}}
  def get_cooldown(signal, who, duration) do
    from(
      cd in Cooldown,
      where: cd.signal == ^signal and cd.who_triggered == ^who,
      select: cd.last_triggered
    )
    |> Repo.one()
    |> case do
      nil ->
        {false, nil}

      naive_datetime ->
        cd_datetime = naive_datetime |> DateTime.from_naive!("Etc/UTC")
        has_cooldown? = Timex.diff(Timex.now(), cd_datetime, :seconds) < duration
        {has_cooldown?, cd_datetime}
    end
  end

  @doc ~s"""
  Mark that at the current time a notification type has been sent for a project
  """
  @spec set_triggered(String.t(), String.t(), %DateTime{}) ::
          {:ok, %Cooldown{}} | {:error, Ecto.Changeset.t()}
  def set_triggered(signal, who, datetime \\ Timex.now()) do
    cd = Repo.get_by(Cooldown, signal: signal, who_triggered: who) || %Cooldown{}

    cd
    |> changeset(%{signal: signal, who_triggered: who, last_triggered: datetime})
    |> Repo.insert_or_update()
  end
end
