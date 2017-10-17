defmodule Sanbase.Repo.Migrations.CreateBtt do
  use Ecto.Migration

  def change do
    create table(:btt) do
      add :project_id, references(:project, type: :serial, on_delete: :nothing), null: false
      add :link, :text
      add :date, :date
      add :total_reads, :integer
      add :post_until_icostart, :integer
      add :post_until_icoend, :integer
      add :posts_total, :integer
    end
    create unique_index(:btt, [:project_id])
  end
end
