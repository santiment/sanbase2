defmodule Sanbase.Repo.Migrations.AddDeepResearchTurnUsage do
  use Ecto.Migration

  @moduledoc """
  Gives the run's usage ledger (elapsed time, tool/model calls, tokens, cost) its own
  column. It is one record per turn, not an event in the transcript, so it used to be
  stored as a `kind: "usage"` entry in `timeline` and filtered back out on render.
  """

  def up() do
    alter table(:deep_research_turns) do
      add(:usage, :map)
    end
  end

  def down() do
    alter table(:deep_research_turns) do
      remove(:usage)
    end
  end
end
