defmodule Sanbase.Repo.Migrations.CreateMetricVersionAliases do
  use Ecto.Migration

  # Day-one rows, all global. The names are data - rename them in the admin UI,
  # not here. See docs/metric-version-aliases.md
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
      # global | category | metric. See the scope_shape check below.
      add(:scope_type, :string, null: false)
      # The metric name for metric scope, "" otherwise. Not NULL on purpose: the
      # partial unique indexes below must treat all global rows as one scope.
      add(:scope_value, :string, null: false, default: "")
      add(:category_id, references(:metric_categories, on_delete: :restrict))
      add(:version_num, :string, null: false)
      # NULL means "no alias in this scope" and shadows a less specific row.
      add(:version_name, :string)
      add(:description, :text)
      add(:priority, :integer, null: false, default: 0)

      timestamps()
    end

    create(
      constraint(:metric_version_aliases, :metric_version_aliases_scope_shape,
        check: """
        (scope_type = 'global' AND scope_value = '' AND category_id IS NULL)
        OR (scope_type = 'metric' AND scope_value <> '' AND category_id IS NULL)
        OR (scope_type = 'category' AND scope_value = '' AND category_id IS NOT NULL)
        """
      )
    )

    create(
      index(:metric_version_aliases, [:scope_type, :scope_value, :version_num],
        unique: true,
        where: "category_id IS NULL",
        name: :metric_version_aliases_scope_version_num_index
      )
    )

    create(
      index(:metric_version_aliases, [:scope_type, :scope_value, :version_name],
        unique: true,
        where: "category_id IS NULL",
        name: :metric_version_aliases_scope_version_name_index
      )
    )

    create(
      index(:metric_version_aliases, [:category_id, :version_num],
        unique: true,
        where: "scope_type = 'category'",
        name: :metric_version_aliases_category_version_num_index
      )
    )

    create(
      index(:metric_version_aliases, [:category_id, :version_name],
        unique: true,
        where: "scope_type = 'category'",
        name: :metric_version_aliases_category_version_name_index
      )
    )

    flush()
    seed()
  end

  def down() do
    drop(table(:metric_version_aliases))
  end

  defp seed() do
    values =
      Enum.map_join(@seed, ",\n", fn {num, name, description} ->
        "('global', '', '#{num}', '#{name}', '#{description}', 0, NOW(), NOW())"
      end)

    execute("""
    INSERT INTO metric_version_aliases
      (scope_type, scope_value, version_num, version_name, description, priority, inserted_at, updated_at)
    VALUES
    #{values}
    """)
  end
end
