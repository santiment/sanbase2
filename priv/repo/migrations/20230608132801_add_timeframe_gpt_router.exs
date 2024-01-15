defmodule Sanbase.Repo.Migrations.AddTimeframeGptRouter do
  use Ecto.Migration

  def change do
    alter table(:gpt_router) do
      add(:timeframe, :integer, default: -1)
    end
  end
end
