defmodule Sanbase.Repo.Migrations.CreateQuestionTypeEnum do
  use Ecto.Migration

  def up do
    execute("""
    DO $$ BEGIN
      CREATE TYPE #{schema()}.question_type AS ENUM ('single_select', 'multi_select', 'open_text', 'open_number', 'boolean');
    EXCEPTION
      WHEN duplicate_object THEN null;
    END $$;
    """)
  end

  def down do
    execute("""
    DROP TYPE IF EXISTS #{schema()}.question_type;
    """)
  end

  def schema() do
    case Sanbase.Utils.Config.module_get(Sanbase, :deployment_env) do
      env when env in ["stage", "prod"] -> "sanbase2"
      _ -> "public"
    end
  end
end
