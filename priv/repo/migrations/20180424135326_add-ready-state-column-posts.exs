defmodule :"Elixir.Sanbase.Repo.Migrations.Add-ready-state-column-posts" do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add(:ready_state, :string, default: "draft")
    end
  end
end
