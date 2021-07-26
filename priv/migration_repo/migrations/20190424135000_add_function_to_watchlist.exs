defmodule Sanbase.Repo.Migrations.AddFunctionToWatchlist do
  use Ecto.Migration

  def change do
    alter table(:user_lists) do
      add(:function, :jsonb,
        default: %Sanbase.WatchlistFunction{} |> Map.from_struct() |> Jason.encode!()
      )
    end
  end
end
