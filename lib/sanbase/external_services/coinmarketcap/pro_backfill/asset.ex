defmodule Sanbase.ExternalServices.Coinmarketcap.ProBackfill.Asset do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo
  alias __MODULE__

  @statuses ~w(pending running completed failed canceled)
  @usage_precisions ~w(exact estimated mixed)

  schema "coinmarketcap_pro_backfill_assets" do
    field(:slug, :string)
    field(:cmc_integer_id, :integer)
    field(:rank, :integer)
    field(:status, :string)
    field(:missing_ranges, :map, default: %{"ranges" => []})
    field(:points_exported, :integer, default: 0)
    field(:api_credits_used, :float, default: 0.0)
    field(:api_calls_total, :integer, default: 0)
    field(:rate_limited_calls_total, :integer, default: 0)
    field(:usage_precision, :string, default: "exact")
    field(:last_error, :string)
    field(:started_at, :utc_datetime)
    field(:finished_at, :utc_datetime)

    belongs_to(:run, Sanbase.ExternalServices.Coinmarketcap.ProBackfill.Run)
    belongs_to(:project, Sanbase.Project)

    timestamps()
  end

  def changeset(%Asset{} = asset, attrs) do
    asset
    |> cast(attrs, [
      :run_id,
      :project_id,
      :slug,
      :cmc_integer_id,
      :rank,
      :status,
      :missing_ranges,
      :points_exported,
      :api_credits_used,
      :api_calls_total,
      :rate_limited_calls_total,
      :usage_precision,
      :last_error,
      :started_at,
      :finished_at
    ])
    |> validate_required([:run_id, :project_id, :slug, :cmc_integer_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:usage_precision, @usage_precisions)
    |> unique_constraint([:run_id, :project_id])
  end

  def get!(id), do: Repo.get!(Asset, id)
  def get(id), do: Repo.get(Asset, id)

  def list_by_run(run_id) do
    from(a in Asset, where: a.run_id == ^run_id, order_by: [asc: a.rank, asc: a.project_id])
    |> Repo.all()
  end

  def list_pending_by_run(run_id) do
    from(a in Asset,
      where: a.run_id == ^run_id and a.status == "pending",
      order_by: [asc_nulls_last: a.rank, desc: a.points_exported, asc: a.project_id]
    )
    |> Repo.all()
  end

  def list_failed_by_run(run_id, limit \\ 10) do
    from(a in Asset,
      where: a.run_id == ^run_id and a.status == "failed",
      order_by: [desc: a.updated_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  def update_asset(%Asset{} = asset, attrs) do
    asset
    |> changeset(attrs)
    |> Repo.update()
  end

  def mark_running(%Asset{} = asset) do
    update_asset(asset, %{status: "running", started_at: asset.started_at || DateTime.utc_now()})
  end

  def mark_completed(%Asset{} = asset, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          status: "completed",
          finished_at: DateTime.utc_now()
        },
        attrs
      )

    update_asset(asset, attrs)
  end

  def mark_failed(%Asset{} = asset, error, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          status: "failed",
          last_error: error,
          finished_at: DateTime.utc_now()
        },
        attrs
      )

    update_asset(asset, attrs)
  end

  def mark_canceled(%Asset{} = asset) do
    update_asset(asset, %{status: "canceled", finished_at: DateTime.utc_now()})
  end

  def insert_many(rows) when is_list(rows) do
    Repo.insert_all(Asset, rows)
  end
end
