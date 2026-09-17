defmodule Sanbase.Repo.Migrations.CreateMetricVersionAliases do
  use Ecto.Migration

  # Day-one rows. The names are data - rename them in the admin UI, not here.
  # See docs/metric-version-aliases.md
  @seed [
    {"1.0", "original:v1", "The original computation. For most metrics the only version."},
    {"2.0", "modern:v1", "Modern computation, v1."},
    {"2.1", "modern_pit:v1", "Point-in-time variant of the modern computation, v1."},
    {"2.1.1", "modern_pit:v1.1", "Point-in-time variant of the modern computation, v1.1."},
    {"2.1.2", "modern_pit:v1.2", "Point-in-time variant of the modern computation, v1.2."},
    {"3.0", "stock:v1", "Stock computation, v1."},
    {"3.1", "stock_pit:v1", "Point-in-time variant of the stock computation, v1."},
    {"Experimental (Weighted Age)", "experimental_weighted_age",
     "Experimental weighted-age implementation. Visible to alpha users only."}
  ]

  def up() do
    create table(:metric_version_aliases) do
      add(:version_num, :string, null: false)
      add(:version_name, :string, null: false)
      add(:description, :text)

      timestamps()
    end

    create(unique_index(:metric_version_aliases, [:version_num]))
    create(unique_index(:metric_version_aliases, [:version_name]))

    flush()
    seed()
  end

  def down() do
    drop(table(:metric_version_aliases))
  end

  defp seed() do
    values =
      Enum.map_join(@seed, ",\n", fn {num, name, description} ->
        "('#{num}', '#{name}', '#{description}', NOW(), NOW())"
      end)

    execute("""
    INSERT INTO metric_version_aliases (version_num, version_name, description, inserted_at, updated_at)
    VALUES
    #{values}
    """)
  end
end
