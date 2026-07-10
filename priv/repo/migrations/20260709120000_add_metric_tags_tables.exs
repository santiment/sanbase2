defmodule Sanbase.Repo.Migrations.AddMetricTagsTables do
  use Ecto.Migration

  @tags [
    {"basic", "Metrics exposed on the Basic bundle plan"},
    {"development_data", "Development activity metrics"},
    {"market_data", "Price and market metrics"},
    {"social_data", "Social volume and sentiment metrics"},
    {"onchain_data", "Onchain and blockchain metrics"}
  ]

  def change do
    create table(:metric_tags) do
      add(:name, :string, null: false)
      add(:description, :text)

      timestamps()
    end

    create(unique_index(:metric_tags, [:name]))

    create table(:metric_tag_mappings) do
      # There's a check constraint that allows either metric_registry_id to be set
      # or module/metric, but not both.
      add(:metric_registry_id, references(:metric_registry, on_delete: :delete_all))
      add(:module, :string)
      add(:metric, :string)

      add(:tag_id, references(:metric_tags, on_delete: :delete_all), null: false)

      timestamps()
    end

    create(index(:metric_tag_mappings, [:tag_id]))

    # Either metric_registry_id is set and module/metric are NULL,
    # or metric_registry_id is NULL and module/metric are both not NULL.
    create(
      constraint(:metric_tag_mappings, :only_one_metric_identifier,
        check: """
        (metric_registry_id IS NOT NULL AND module IS NULL AND metric IS NULL)
        OR
        (metric_registry_id IS NULL AND module IS NOT NULL AND metric IS NOT NULL)
        """
      )
    )

    # A registry-backed metric can carry many tags, but not the same tag twice.
    create(
      index(:metric_tag_mappings, [:metric_registry_id, :tag_id],
        unique: true,
        where: "metric_registry_id IS NOT NULL"
      )
    )

    # A module/metric pair can carry many tags, but not the same tag twice.
    create(
      index(:metric_tag_mappings, [:module, :metric, :tag_id],
        unique: true,
        where: "module IS NOT NULL AND metric IS NOT NULL"
      )
    )

    seed_tags()
  end

  defp seed_tags() do
    values =
      @tags
      |> Enum.map_join(",\n", fn {name, description} ->
        "('#{name}', '#{description}', NOW(), NOW())"
      end)

    execute(
      """
      INSERT INTO metric_tags (name, description, inserted_at, updated_at) VALUES
      #{values}
      ON CONFLICT (name) DO NOTHING
      """,
      """
      DELETE FROM metric_tags WHERE name IN (#{Enum.map_join(@tags, ",", fn {name, _} -> "'#{name}'" end)})
      """
    )
  end
end
