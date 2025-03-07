defmodule Sanbase.Repo.Migrations.CreateMetricRegistry do
  use Ecto.Migration

  # We have JSON records that define single metrics:

  # {
  #   "human_readable_name": "USD Price",
  #   "name": "price_usd_5m",
  #   "metric": "price_usd",
  #   "version": "2019-01-01",
  #   "access": "free",
  #   "selectors": [
  #     "slug"
  #   ],
  #   "min_plan": {
  #     "SANAPI": "free",
  #     "SANBASE": "free"
  #   },
  #   "aggregation": "last",
  #   "min_interval": "5m",
  #   "table": "intraday_metrics",
  #   "has_incomplete_data": false,
  #   "data_type": "timeseries",
  #   "docs_links": ["https://academy.santiment.net/metrics/price"]
  # }

  # But we also have metrics that define multiple metrics using templates

  # {
  #   "human_readable_name": "Mean Realized USD Price for coins that moved in the past {{timebound:human_readable}}",
  #   "name": "mean_realized_price_usd_{{timebound}}",
  #   "metric": "mean_realized_price_usd_{{timebound}}",
  #   "parameters": [
  #     { "timebound": "1d" },
  #     { "timebound": "7d" },
  #     { "timebound": "30d" },
  #     { "timebound": "60d" },
  #     { "timebound": "90d" },
  #     { "timebound": "180d" },
  #     { "timebound": "365d" },
  #     { "timebound": "2y" },
  #     { "timebound": "3y" },
  #     { "timebound": "5y" },
  #     { "timebound": "10y" }
  #   ],
  #   "is_timebound": true,
  #   "version": "2019-01-01",
  #   "access": "restricted",
  #   "selectors": [ "slug" ],
  #   "min_plan": {
  #     "SANAPI": "free",
  #     "SANBASE": "free"
  #   },
  #   "aggregation": "avg",
  #   "min_interval": "1d",
  #   "table": "daily_metrics_v2",
  #   "has_incomplete_data": true,
  #   "data_type": "timeseries",
  #   "docs_links": ["https://academy.santiment.net/metrics/mean-realized-price"]
  # }
  def change do
    create table(:metric_registry) do
      add(:metric, :string, null: false)
      add(:internal_metric, :string, null: false)
      add(:human_readable_name, :string, null: false)
      add(:aliases, :map)
      add(:tables, :map, null: false)

      add(:is_template, :boolean, null: false, default: false)
      add(:parameters, :map, null: false, default: "{}")
      add(:fixed_parameters, :map, null: "false", default: "{}")

      add(:is_timebound, :boolean, null: false, null: false)
      add(:exposed_environments, :string, null: false, default: "all")

      add(:version, :string)
      add(:selectors, :map)
      add(:required_selectors, :map)

      add(:access, :string, null: false)
      add(:sanbase_min_plan, :string, null: false, default: "free")
      add(:sanapi_min_plan, :string, null: false, default: "free")

      add(:default_aggregation, :string, null: false)
      add(:min_interval, :string, null: false)
      add(:has_incomplete_data, :boolean, null: false)
      add(:data_type, :string, null: false, default: "timeseries")
      add(:docs, :map)

      add(:is_hidden, :boolean, null: false, default: false)
      add(:is_deprecated, :boolean, null: false, default: false)
      add(:hard_deprecate_after, :utc_datetime, null: true, default: nil)
      add(:deprecation_note, :text, null: true, default: nil)

      timestamps(type: :timestamptz)
    end

    create(
      unique_index(:metric_registry, [:metric, :data_type, :fixed_parameters],
        name: :metric_registry_composite_unique_index
      )
    )
  end
end
