defmodule Sanbase.Repo.Migrations.MoveVersionAliasesToSocialScope do
  use Ecto.Migration

  # The modern and stock names move to the "social" scope, as do the registry
  # metrics of the Social category. "original:v1" (1.0) stays global and applies
  # to every metric.

  def up() do
    execute("""
    UPDATE metric_version_aliases
    SET scope = 'social', updated_at = NOW()
    WHERE scope = 'global' AND version_num <> '1.0'
    """)

    execute("""
    UPDATE metric_registry
    SET version_scope = 'social'
    WHERE id IN (
      SELECT m.metric_registry_id
      FROM metric_category_mappings m
      JOIN metric_categories c ON c.id = m.category_id
      WHERE c.name = 'Social' AND m.metric_registry_id IS NOT NULL
    )
    """)
  end

  def down() do
    execute("UPDATE metric_registry SET version_scope = 'global' WHERE version_scope = 'social'")

    # A social row that overrides a global one has nowhere to go.
    execute("""
    DELETE FROM metric_version_aliases s
    USING metric_version_aliases g
    WHERE s.scope = 'social' AND g.scope = 'global'
      AND (s.version_num = g.version_num OR s.version_name = g.version_name)
    """)

    execute("""
    UPDATE metric_version_aliases
    SET scope = 'global', updated_at = NOW()
    WHERE scope = 'social'
    """)
  end
end
