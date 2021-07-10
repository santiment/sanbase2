defmodule Sanbase.Repo.Migrations.AddObanJobs do
  use Ecto.Migration

  def up do
    Oban.Migrations.up(prefix: "sanbase_scrapers")
  end

  # We specify `version: 1` in `down`, ensuring that we'll roll all the way back down if
  # necessary, regardless of which version we've migrated `up` to.
  def down do
    Oban.Migrations.down(prefix: "sanbase_scrapers", version: 1)
  end
end
