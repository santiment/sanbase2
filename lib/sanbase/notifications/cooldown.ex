defmodule Sanbase.Notifications.Cooldown do
  @moduledoc ~s"""
  Handle cooldowns.
  """

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

  def has_cooldown?(signal, who, duration, duration_format \\ :seconds) do
    from(
      cd in Cooldown,
      where: cd.signal == ^signal and cd.who_triggered == ^who,
      select: cd.last_triggered
    )
    |> Repo.one()
    |> case do
      nil ->
        false

      naive_datetime ->
        datetime = naive_datetime |> DateTime.from_naive!("Etc/UTC")
        Timex.diff(Timex.now(), datetime, duration_format) < duration
    end
  end

  def set_triggered(signal, who, datetime \\ Timex.now()) do
    cd = Repo.get_by(Cooldown, signal: signal, who_triggered: who) || %Cooldown{}

    cd
    |> changeset(%{signal: signal, who_triggered: who, last_triggered: datetime})
    |> Repo.insert_or_update()
  end
end
