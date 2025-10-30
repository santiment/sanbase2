defmodule Sanbase.Repo.Migrations.ImproveCategorizationUniqueIndex do
  use Ecto.Migration

  def change do
    drop(unique_index(:metric_categories, [:name]))
    drop(unique_index(:metric_groups, [:name, :category_id]))

    create(
      unique_index(:metric_categories, ["(lower(name))"], name: :metric_categories_name_index)
    )

    create(
      unique_index(:metric_groups, ["(lower(name))", :category_id],
        name: :metric_groups_name_category_id_index
      )
    )
  end
end
