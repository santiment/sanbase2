defmodule Sanbase.Repo.Migrations.AddUniqueIndexSignUpTrials do
  @moduledoc false
  use Ecto.Migration

  def up do
    drop(index(:sign_up_trials, [:user_id]))
    create(unique_index(:sign_up_trials, [:user_id]))
  end

  def down do
    drop(unique_index(:sign_up_trials, [:user_id]))
    create(index(:sign_up_trials, [:user_id]))
  end
end
