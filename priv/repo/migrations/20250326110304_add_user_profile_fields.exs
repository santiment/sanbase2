defmodule Sanbase.Repo.Migrations.AddUserProfileFields do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # Text field for user's description/bio
      add(:description, :text)

      # Social links
      add(:twitter_url, :string)
      add(:website_url, :string)
    end
  end
end
