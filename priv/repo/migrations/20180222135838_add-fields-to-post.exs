defmodule :"Elixir.Sanbase.Repo.Migrations.Add-fields-to-post" do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add(:short_desc, :text)
      add(:text, :text)

      modify(:link, :text, null: true)
    end
  end
end
