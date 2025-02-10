defmodule Sanbase.Repo.Migrations.CreateWebinars do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:webinars) do
      add(:title, :string)
      add(:description, :text)
      add(:url, :string)
      add(:image_url, :string)
      add(:start_time, :utc_datetime)
      add(:end_time, :utc_datetime)
      add(:is_pro, :boolean, default: false, null: false)

      timestamps()
    end
  end
end
