defmodule :"Elixir.Sanbase.Repo.Migrations.Add-consentId-users" do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:consent_id, :string)
    end
  end
end
