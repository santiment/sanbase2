defmodule Sanbase.Repo.Migrations.AddActiveWidgetsTable do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:active_widgets) do
      add(:title, :string, null: false)
      add(:description, :string)
      add(:is_active, :boolean, default: true)
      add(:image_link, :string)
      add(:video_link, :string)

      timestamps()
    end
  end
end
