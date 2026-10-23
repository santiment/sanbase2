Code.require_file("priv/repo/migrations/20261014084308_create_metric_version_plan_access.exs")

defmodule Sanbase.Billing.Plan.MetricVersionSeedTest do
  @moduledoc ~s"""
  The plan access the migration seeds, for the alias rows the earlier migrations leave
  and for versions of every shape its patterns tell apart. The expected rows are the
  rules that were hardcoded before the migration.
  """
  use Sanbase.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Sanbase.Metric.VersionAlias
  alias Sanbase.Metric.VersionPlanAccess
  alias Sanbase.Repo
  alias Sanbase.Repo.Migrations.CreateMetricVersionPlanAccess

  @everyone [{"SANAPI", "ANY", "any", true}, {"SANBASE", "ANY", "any", true}]
  @business [
    {"SANAPI", "BUSINESS_MAX", "any", true},
    {"SANAPI", "BUSINESS_PRO", "any", true},
    {"SANBASE", "ANY", "any", true}
  ]
  @pit [{"SANAPI", "BUSINESS_MAX", "year", false}, {"SANBASE", "ANY", "any", true}]

  # {scope, version, name, expected plan access}
  @rows [
    # Left by the alias migrations
    {"global", "1.0", "original:v1", @everyone},
    {"global", "Experimental (Weighted Age)", "experimental_weighted_age:v1", []},
    {"social", "2.0", "modern:v1", @business},
    {"social", "2.1", "modern_pit:v1", @pit},
    {"social", "2.1.1", "modern_pit:v1.1", @pit},
    {"social", "2.1.2", "modern_pit:v1.2", @pit},
    {"social", "3.0", "stock:v1", @business},
    {"social", "3.1", "stock_pit:v1", @pit},
    {"github", "2.0", "modern:v1", @everyone},
    # Other shapes
    {"global", "1.1", "shape_base:v1", @everyone},
    {"global", "1.0.1", "shape_base:v2", @everyone},
    {"global", "2.0.1", "shape_standard:v1", @business},
    {"global", "10.0", "shape_standard:v2", @business},
    {"global", "4.1.1", "shape_pit:v1", @pit},
    {"global", "10.2", "shape_pit:v2", @pit},
    {"github", "3.1", "shape_github:v1", @everyone}
  ]

  test "every alias row gets the plan access of the rules it replaces" do
    Repo.delete_all(VersionAlias)

    for {scope, num, name, _} <- @rows do
      {:ok, _} = VersionAlias.create(%{scope: scope, version_num: num, version_name: name})
    end

    for sql <- CreateMetricVersionPlanAccess.seed_sql(), do: Repo.query!(sql)

    seeded =
      from(p in VersionPlanAccess,
        join: a in assoc(p, :version_alias),
        select:
          {a.scope, a.version_num, {p.product, p.plan, p.billing_interval, p.accessible_if_trial}}
      )
      |> Repo.all()
      |> Enum.group_by(fn {scope, num, _} -> {scope, num} end, fn {_, _, access} -> access end)

    for {scope, num, _name, expected} <- @rows do
      assert Enum.sort(Map.get(seeded, {scope, num}, [])) == Enum.sort(expected),
             "#{scope} #{num}"
    end
  end
end
