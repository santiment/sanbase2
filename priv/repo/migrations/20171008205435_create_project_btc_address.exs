defmodule Sanbase.Repo.Migrations.CreateProjectBtcAddress do
  use Ecto.Migration

  def change do
    create table(:project_btc_address) do
      add :address, :string, null: false
      add :project_id, references(:project, on_delete: :delete_all)
    end

    create unique_index(:project_btc_address, [:address])
    create index(:project_btc_address, [:project_id])
  end
end
