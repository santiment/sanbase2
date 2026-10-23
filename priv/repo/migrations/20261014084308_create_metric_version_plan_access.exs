defmodule Sanbase.Repo.Migrations.CreateMetricVersionPlanAccess do
  use Ecto.Migration

  # Which plans may use a version. Each row lets one plan use one alias row on one
  # product (the surface the request comes through). The seed gives every existing
  # alias row the answer the rules that were in code before gave it (see
  # metric_version_seed_parity_test.exs). A version with no alias row in its scope gets
  # nothing, so it is denied where the old rules decided by its number:
  #
  #   * the github scope and the 1.x versions - every plan, on both products;
  #   * Sanbase - every plan, every version;
  #   * SanAPI X.0 versions - Business Pro and Business Max;
  #   * SanAPI point-in-time versions (X.Y, Y > 0) - yearly Business Max, not on trial.
  #
  # Non-numeric versions ("Experimental (Weighted Age)") have their own alpha-only rule
  # and get no rows.

  @numeric "^[0-9]+(\\.[0-9]+)+$"
  @base "^1\\."
  @standard "^[0-9]+\\.0(\\.[0-9]+)*$"

  def up() do
    create table(:metric_version_plan_access) do
      add(:version_alias_id, references(:metric_version_aliases, on_delete: :delete_all),
        null: false
      )

      add(:product, :string, null: false)
      add(:plan, :string, null: false)
      add(:billing_interval, :string, null: false, default: "any")
      add(:accessible_if_trial, :boolean, null: false, default: true)

      timestamps()
    end

    create(
      unique_index(
        :metric_version_plan_access,
        [:version_alias_id, :product, :plan, :billing_interval],
        name: :metric_version_plan_access_unique_index
      )
    )

    Enum.each(seed_sql(), &execute/1)
  end

  @doc "The INSERTs that seed the plan access, in order. Public so a test can run them."
  def seed_sql() do
    [
      seed("""
      SELECT a.id, p.product, 'ANY', 'any', true
      FROM metric_version_aliases a
      CROSS JOIN (VALUES ('SANAPI'), ('SANBASE')) AS p(product)
      WHERE a.version_num ~ '#{@numeric}'
        AND (a.scope = 'github' OR a.version_num ~ '#{@base}')
      """),
      seed("""
      SELECT a.id, 'SANBASE', 'ANY', 'any', true
      FROM metric_version_aliases a
      WHERE a.version_num ~ '#{@numeric}'
      """),
      seed("""
      SELECT a.id, 'SANAPI', p.plan, 'any', true
      FROM metric_version_aliases a
      CROSS JOIN (VALUES ('BUSINESS_PRO'), ('BUSINESS_MAX')) AS p(plan)
      WHERE a.scope != 'github'
        AND a.version_num ~ '#{@standard}' AND a.version_num !~ '#{@base}'
      """),
      seed("""
      SELECT a.id, 'SANAPI', 'BUSINESS_MAX', 'year', false
      FROM metric_version_aliases a
      WHERE a.scope != 'github'
        AND a.version_num ~ '#{@numeric}'
        AND a.version_num !~ '#{@standard}' AND a.version_num !~ '#{@base}'
      """)
    ]
  end

  def down() do
    drop(table(:metric_version_plan_access))
  end

  defp seed(select) do
    """
    INSERT INTO metric_version_plan_access
      (version_alias_id, product, plan, billing_interval, accessible_if_trial, inserted_at, updated_at)
    SELECT s.*, NOW(), NOW() FROM (#{select}) AS s
    ON CONFLICT DO NOTHING
    """
  end
end
