defmodule :"Elixir.Sanbase.Repo.Migrations.Create-signals-cooldown-table" do
  use Ecto.Migration

  def change do
    create table("signal-cooldowns") do
      add(:signal, :string, null: false)
      add(:who_triggered, :string, null: false)
      add(:last_triggered, :naive_datetime)
    end
  end
end
