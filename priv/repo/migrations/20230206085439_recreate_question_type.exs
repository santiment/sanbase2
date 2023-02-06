defmodule Sanbase.Repo.Migrations.RecreateQuestionType do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TYPE #{schema()}.question_type RENAME VALUE 'multi_select' TO 'multiple_select';
    """)
  end

  def down do
    execute("""
    ALTER TYPE #{schema()}.question_type RENAME VALUE 'multiple_select' TO 'multi_select';
    """)
  end

  def schema() do
    case Sanbase.Utils.Config.module_get(Sanbase, :deployment_env) do
      env when env in ["stage", "prod"] -> "sanbase2"
      _ -> "public"
    end
  end
end
