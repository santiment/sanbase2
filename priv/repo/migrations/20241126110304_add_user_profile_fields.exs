defmodule Sanbase.Repo.Migrations.AddUserProfileFields do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # Text field for user's description/bio
      add(:description, :text)

      # Boolean flag for Santiment team membership
      add(:is_santiment_team, :boolean, default: false)

      # Social links
      add(:twitter_link, :string)
      add(:website_link, :string)
    end

    create(index(:users, [:is_santiment_team]))
  end
end
