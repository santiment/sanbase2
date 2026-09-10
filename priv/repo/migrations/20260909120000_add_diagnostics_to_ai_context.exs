defmodule Sanbase.Repo.Migrations.AddDiagnosticsToAiContext do
  use Ecto.Migration

  @moduledoc """
  Makes failed and degraded bot turns visible in the database.

  Until now a row was written only when the AI server answered successfully, so
  a question that errored left no trace outside the application logs. These
  columns carry the diagnostics the AI server now returns alongside the answer.
  """

  def change do
    alter table(:ai_context) do
      # "ok" | "degraded" | "error". Existing rows are successful answers.
      add(:status, :string, default: "ok")
      # "v1" | "v2" - which QA engine produced the answer.
      add(:qa_engine, :string)
      # True when the v2 orchestrator raised and v1 answered instead.
      add(:v2_fallback, :boolean, default: false)
      # The standalone question actually sent downstream, when it was rewritten.
      add(:rephrased_question, :text)
      # Tool names the v2 orchestrator called.
      add(:tools_used, {:array, :string}, default: [])
      # Langfuse trace id, so a row links straight to its trace.
      add(:langfuse_trace_id, :string)
    end

    # Error rows are the ones we go looking for, and they are a small minority.
    create(index(:ai_context, [:status], where: "status <> 'ok'"))
  end
end
