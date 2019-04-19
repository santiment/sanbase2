defmodule Sanbase.Repo.Migrations.AddFunctionToWatchlist do
  use Ecto.Migration

  def change do
    alter table(:user_lists) do
      add(:function, :jsonb)
    end
  end
end
