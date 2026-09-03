defmodule Sanbase.Repo.Migrations.AddQueuedDeepResearchPhase do
  use Ecto.Migration

  @moduledoc """
  Adds the `queued` phase: a turn submitted to the agent server that no worker has
  picked up yet. It replaces `planning` as a new turn's initial phase, so the UI can
  tell "waiting in the server's queue" from "the agent is planning".
  """

  def up() do
    drop(constraint(:deep_research_turns, :valid_phase))

    create(
      constraint(:deep_research_turns, :valid_phase,
        check:
          "phase IN ('idle','queued','planning','researching','writing','awaiting_user','paused','completed','failed','cancelled')"
      )
    )
  end

  def down() do
    # Lock first: a 'queued' row written after the UPDATE would fail the constraint.
    execute("LOCK TABLE deep_research_turns IN ACCESS EXCLUSIVE MODE")
    execute("UPDATE deep_research_turns SET phase = 'planning' WHERE phase = 'queued'")

    drop(constraint(:deep_research_turns, :valid_phase))

    create(
      constraint(:deep_research_turns, :valid_phase,
        check:
          "phase IN ('idle','planning','researching','writing','awaiting_user','paused','completed','failed','cancelled')"
      )
    )
  end
end
