defmodule Sanbase.Repo.Migrations.AddEtherscanOfficialLinksToProjects do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:project) do
      add(:email, :string)
      add(:bitcointalk_link, :string)
    end
  end
end
