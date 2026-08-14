defmodule Sanbase.Repo.Migrations.AddPausedDeepResearchPhase do
  use Ecto.Migration

  @moduledoc "Adds the `paused` phase: an interrupted run the user can continue."

  def up() do
    drop(constraint(:deep_research_turns, :valid_phase))

    create(
      constraint(:deep_research_turns, :valid_phase,
        check:
          "phase IN ('idle','planning','researching','writing','awaiting_user','paused','completed','failed','cancelled')"
      )
    )
  end

  def down() do
    # Lock first: a 'paused' row written after the UPDATE would fail the constraint.
    execute("LOCK TABLE deep_research_turns IN ACCESS EXCLUSIVE MODE")
    execute("UPDATE deep_research_turns SET phase = 'failed' WHERE phase = 'paused'")

    drop(constraint(:deep_research_turns, :valid_phase))

    create(
      constraint(:deep_research_turns, :valid_phase,
        check:
          "phase IN ('idle','planning','researching','writing','awaiting_user','completed','failed','cancelled')"
      )
    )
  end
end
