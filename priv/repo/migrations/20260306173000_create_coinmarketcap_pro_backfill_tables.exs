defmodule Sanbase.Repo.Migrations.CreateCoinmarketcapProBackfillTables do
  use Ecto.Migration

  def change do
    create table(:coinmarketcap_pro_backfill_runs) do
      add(:source, :string, null: false, default: "coinmarketcap")
      add(:scope, :string, null: false)
      add(:status, :string, null: false, default: "pending")
      add(:interval, :string, null: false, default: "5m")
      add(:time_start, :utc_datetime, null: false)
      add(:time_end, :utc_datetime, null: false)
      add(:dry_run, :boolean, null: false, default: false)
      add(:total_assets, :integer, null: false, default: 0)
      add(:done_assets, :integer, null: false, default: 0)
      add(:failed_assets, :integer, null: false, default: 0)
      add(:pending_assets, :integer, null: false, default: 0)
      add(:api_credits_used_total, :float, null: false, default: 0.0)
      add(:api_calls_total, :integer, null: false, default: 0)
      add(:rate_limited_calls_total, :integer, null: false, default: 0)
      add(:usage_precision, :string, null: false, default: "exact")
      add(:last_error, :text)
      add(:started_at, :utc_datetime)
      add(:finished_at, :utc_datetime)

      timestamps()
    end

    create(index(:coinmarketcap_pro_backfill_runs, [:status]))
    create(index(:coinmarketcap_pro_backfill_runs, [:inserted_at]))

    create table(:coinmarketcap_pro_backfill_assets) do
      add(:run_id, references(:coinmarketcap_pro_backfill_runs, on_delete: :delete_all),
        null: false
      )

      add(:project_id, :integer, null: false)
      add(:slug, :string, null: false)
      add(:cmc_integer_id, :integer, null: false)
      add(:rank, :integer)
      add(:status, :string, null: false, default: "pending")
      add(:missing_ranges, :map, null: false, default: %{})
      add(:points_exported, :integer, null: false, default: 0)
      add(:api_credits_used, :float, null: false, default: 0.0)
      add(:api_calls_total, :integer, null: false, default: 0)
      add(:rate_limited_calls_total, :integer, null: false, default: 0)
      add(:usage_precision, :string, null: false, default: "exact")
      add(:last_error, :text)
      add(:started_at, :utc_datetime)
      add(:finished_at, :utc_datetime)

      timestamps()
    end

    create(unique_index(:coinmarketcap_pro_backfill_assets, [:run_id, :project_id]))
    create(index(:coinmarketcap_pro_backfill_assets, [:run_id, :status]))
    create(index(:coinmarketcap_pro_backfill_assets, [:run_id, :rank]))
    create(index(:coinmarketcap_pro_backfill_assets, [:slug]))
  end
end
