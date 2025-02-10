defmodule Sanbase.Repo.Migrations.AddUserIsProToAiContext do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:ai_context) do
      add(:user_is_pro, :boolean, default: false)
    end
  end
end
