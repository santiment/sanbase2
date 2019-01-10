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

  schema "schedule_rescrape_prices" do
    belongs_to(:project, Project)
    field(:from, :naive_datetime)
    field(:to, :naive_datetime)
    field(:in_progress, :boolean, default: false)
    field(:finished, :boolean, default: false)
    field(:original_last_updated, :naive_datetime)

    timestamps()
  end

  @doc false
  def changeset(
        %ScheduleRescrapePrice{} = srp,
        attrs \\ %{}
      ) do
    srp
    |> cast(attrs, [:project_id, :from, :to, :in_progress, :finished, :original_last_updated])
    |> validate_required([:from, :to, :in_progress, :finished, :original_last_updated])
    |> unique_constraint(:project_id)
  end

  def set_original_last_updated(%ScheduleRescrapePrice{} = srp) do
    srp = srp |> Repo.preload([:project])

    original_last_updated =
      Project.by_id(srp.project.id)
      |> Map.get(:coinmarketcap_id)
      |> Sanbase.Prices.Store.last_history_datetime_cmc()
      |> case do
        {:ok, %DateTime{} = datetime} ->
          datetime
          |> DateTime.to_naive()

        _ ->
          nil
      end

    %ScheduleRescrapePrice{
      srp
      | original_last_updated: original_last_updated
    }
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
