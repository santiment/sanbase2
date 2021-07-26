defmodule :"Elixir.Sanbase.Repo.Migrations.Add-posts-projects-link-table" do
  use Ecto.Migration

  def change do
    create table(:posts_projects) do
      add(:post_id, references(:posts))
      add(:project_id, references(:project))
    end

    create(unique_index(:posts_projects, [:post_id, :project_id]))
  end
end
