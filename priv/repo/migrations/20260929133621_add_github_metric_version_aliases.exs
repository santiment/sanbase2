defmodule Sanbase.Repo.Migrations.AddGithubMetricVersionAliases do
  use Ecto.Migration

  # Same names as the social scope, different computations.
  @seed [
    {"2.0", "modern:v1",
     "Counts only the pushes, pull requests, reviews and releases, excludes the bot accounts and the automation running under personal accounts, counts the same event stored twice once and caps the daily events of a contributor per repository."}
  ]

  def up() do
    values =
      Enum.map_join(@seed, ",\n", fn {num, name, description} ->
        "('github', '#{num}', '#{name}', '#{description}', NOW(), NOW())"
      end)

    execute("""
    INSERT INTO metric_version_aliases (scope, version_num, version_name, description, inserted_at, updated_at)
    VALUES
    #{values}
    ON CONFLICT DO NOTHING
    """)
  end

  # Only the seeded aliases, the ones added later by an admin are kept
  def down() do
    for {num, name, _description} <- @seed do
      execute("""
      DELETE FROM metric_version_aliases
      WHERE scope = 'github' AND version_num = '#{num}' AND version_name = '#{name}'
      """)
    end
  end
end
