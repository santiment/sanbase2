defmodule Sanbase.Notifications.Notification do
  @moduledoc ~s"""
  Handles when a notification was sent.
  This module is used to calculate cooldowns.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias __MODULE__

  alias Sanbase.Notifications.Type
  alias Sanbase.Model.Project
  alias Sanbase.Repo

  @table "notifications"

  schema @table do
    belongs_to(:project, Project)
    belongs_to(:type, Type)
    field(:data, :string)

    timestamps()
  end

  @doc false
  def changeset(%Notification{} = notification, attrs \\ %{}) do
    notification
    |> cast(attrs, [:project_id, :type_id, :data, :updated_at])
    |> validate_required([:project_id, :type_id])
  end

  @doc ~s"""
  Return whether a given notification type has been sent for a project
  in the past `duration` seconds
  """
  @spec has_cooldown?(%Project{}, %Type{}, non_neg_integer(), Atom.t()) :: boolean()
  def has_cooldown?(%Project{} = project, %Type{} = type, duration, duration_type \\ :seconds) do
    {has_cooldown?, _} = get_cooldown(project, type, duration, duration_type)
    has_cooldown?
  end

  @spec set_triggered(%Project{}, %Type{}, %DateTime{}) ::
          {:ok, %Notification{}} | {:error, Ecto.Changeset.t()}
  def set_triggered(%Project{id: project_id}, %Type{id: type_id}, datetime \\ DateTime.utc_now()) do
    (Repo.get_by(Notification, project_id: project_id, type_id: type_id) || %Notification{})
    |> changeset(%{project_id: project_id, type_id: type_id, updated_at: datetime})
    |> Repo.insert_or_update()
  end

  def insert_triggered(
        %Project{id: project_id},
        %Type{id: type_id},
        data,
        datetime \\ DateTime.utc_now()
      ) do
    (Repo.get_by(Notification, project_id: project_id, type_id: type_id) || %Notification{})
    |> changeset(%{project_id: project_id, type_id: type_id, data: data, updated_at: datetime})
    |> Repo.insert()
  end

  @doc ~s"""
  Return a tuple where the first argument shows whether a given notification type
  has been sent for a project in the past `duration` seconds.
  If there is a notification sent in the past `duration` seconds, the second argument
  is the datetime that it was sent.
  """
  @spec get_cooldown(String.t(), String.t(), non_neg_integer(), Atom.t()) ::
          {false, nil} | {false, %DateTime{}} | {true, %DateTime{}}
  def get_cooldown(
        %Project{id: project_id},
        %Type{id: type_id},
        duration,
        duration_format \\ :seconds
      ) do
    Notification
    |> where(project_id: ^project_id, type_id: ^type_id)
    |> Repo.one()
    |> case do
      nil ->
        {false, nil}

      %Notification{updated_at: naive_datetime} ->
        cd_datetime = naive_datetime |> DateTime.from_naive!("Etc/UTC")
        has_cooldown? = Timex.diff(Timex.now(), cd_datetime, duration_format) < duration
        {has_cooldown?, cd_datetime}
    end
  end
end
