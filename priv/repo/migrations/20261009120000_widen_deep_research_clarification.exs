defmodule Sanbase.Repo.Migrations.WidenDeepResearchClarification do
  use Ecto.Migration

  @moduledoc """
  Clarification questions are the agent's prose and run past 255 characters; the
  `varchar(255)[]` column made saving such a turn raise.
  """

  def up() do
    alter table(:deep_research_turns) do
      modify(:clarification, {:array, :text}, default: [])
    end
  end

  # Questions longer than 255 characters are what `up` allows, and Postgres refuses to cast
  # them back to `varchar(255)`: cut each one to 255 first, keeping the order.
  def down() do
    execute("""
    UPDATE deep_research_turns
    SET clarification = ARRAY(
      SELECT left(question, 255)
      FROM unnest(clarification) WITH ORDINALITY AS q(question, i)
      ORDER BY i
    )
    WHERE EXISTS (SELECT 1 FROM unnest(clarification) AS q(question) WHERE length(question) > 255)
    """)

    alter table(:deep_research_turns) do
      modify(:clarification, {:array, :string}, default: [])
    end
  end
end
