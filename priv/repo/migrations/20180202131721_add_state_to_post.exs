defmodule Sanbase.Repo.Migrations.AddStateToPost do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:posts) do
      remove(:approved_at)

      add(:state, :string)
      add(:moderation_comment, :string)
    end
  end
end
