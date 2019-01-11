defmodule Sanbase.ExternalServices.Coinmarketcap.ScheduleRescrapePrice do
  @moduledoc ~s"""
  A module that can be interacted with via the admin dashboard.
  It allows to easily schedule rescrapes for prices from coinmarketcap.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias __MODULE__
  alias Sanbase.Repo
  alias Sanbase.Model.Project
  alias Sanbase.DateTimeUtils

  schema "schedule_rescrape_prices" do
    belongs_to(:project, Project)
    field(:from, :naive_datetime)
    field(:to, :naive_datetime)
    field(:in_progress, :boolean, default: false)
    field(:finished, :boolean, default: false)
    field(:original_last_updated, :naive_datetime)

    timestamps()
  end

  def changeset(srp, attrs \\ %{})

  def changeset(
        %ScheduleRescrapePrice{} = srp,
        %{
          original_last_updated: %{day: _, hour: _, min: _, month: _, year: _} = olu
        } = attrs
      ) do
    {:ok, olu} = DateTimeUtils.ExAdmin.to_naive(olu)

    attrs = attrs |> Map.put(:original_last_updated, olu)
    changeset(srp, attrs)
  end

  def changeset(
        %ScheduleRescrapePrice{} = srp,
        %{
          from: %{day: _, hour: _, min: _, month: _, year: _} = from,
          to: %{day: _, hour: _, min: _, month: _, year: _} = to
        } = attrs
      ) do
    {:ok, from} = DateTimeUtils.ExAdmin.to_naive(from)
    {:ok, to} = DateTimeUtils.ExAdmin.to_naive(to)

    attrs = attrs |> Map.put(:from, from) |> Map.put(:to, to)
    changeset(srp, attrs)
  end

  @doc false
  def changeset(
        %ScheduleRescrapePrice{} = srp,
        attrs
      ) do
    srp
    |> cast(attrs, [:project_id, :from, :to, :in_progress, :finished, :original_last_updated])
    |> validate_required([:project_id, :from, :to])
    |> unique_constraint(:project_id)
  end

  @spec get_by_project_id(non_neg_integer) :: %ScheduleRescrapePrice{} | nil
  def get_by_project_id(project_id) do
    Repo.get_by(ScheduleRescrapePrice, project_id: project_id)
  end

  @spec delete_by_project_id(non_neg_integer()) :: {integer(), nil | [term()]}
  def delete_by_project_id(project_id) do
    from(srp in ScheduleRescrapePrice,
      where: srp.project_id == ^project_id
    )
    |> Repo.delete_all()
  end

  def update(changeset) do
    Repo.update(changeset)
  end

  def all_not_started() do
    all_query()
    |> where([p], p.in_progress == false and p.finished == false)
    |> Repo.all()
  end

  def all_in_progress() do
    all_query()
    |> where([p], p.in_progress == true and p.finished == false)
    |> Repo.all()
  end

  defp all_query(), do: from(p in ScheduleRescrapePrice, preload: :project)
end
