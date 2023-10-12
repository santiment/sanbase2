defmodule Elixir.Sanbase.Repo.Migrations.AddDashboardTextWidget do
  use Ecto.Migration

  def change do
    alter table(:dashboards) do
      add(:text_widgets, :jsonb)
    end
  end
end
