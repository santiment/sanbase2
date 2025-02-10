defmodule Sanbase.Repo.Migrations.AddFeaturedChartConfiguration do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:featured_items) do
      add(:chart_configuration_id, references(:chart_configurations))
    end

    fk_check = """
    (CASE WHEN post_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN user_list_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN user_trigger_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN chart_configuration_id IS NULL THEN 0 ELSE 1 END) = 1
    """

    drop(constraint(:featured_items, :only_one_fk))
    create(constraint(:featured_items, :only_one_fk, check: fk_check))
    create(unique_index(:featured_items, [:chart_configuration_id]))
  end
end
