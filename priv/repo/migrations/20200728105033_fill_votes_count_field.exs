defmodule Sanbase.Repo.Migrations.FillVotesCountField do
  use Ecto.Migration

  def change do
  end
end

defmodule Sanbase.Repo.Migrations.FillVotesCountField do
  use Ecto.Migration

  def up do
    setup()
    fill_count()
  end

  def down do
    :ok
  end

  defp fill_count() do
    Sanbase.Repo.update_all(Sanbase.Vote, set: [count: 1])
  end

  defp setup() do
    Application.ensure_all_started(:tzdata)
  end
end
