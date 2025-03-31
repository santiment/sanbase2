defmodule Sanbase.Repo.Migrations.AddUserProfileFields do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # Text field for user's description/bio
      add(:description, :text)

      # Social links
      add(:website_url, :string)
      add(:twitter_handle, :string)
    end
  end
end
