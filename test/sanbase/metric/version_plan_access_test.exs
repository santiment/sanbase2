defmodule Sanbase.Metric.VersionPlanAccessTest do
  use Sanbase.DataCase, async: false

  import Sanbase.MetricVersionAliasHelpers, only: [create_alias!: 1]

  alias Sanbase.Repo
  alias Sanbase.Metric.VersionAlias
  alias Sanbase.Metric.VersionPlanAccess

  setup do
    VersionAlias.clear_cache()
    %{version_alias: create_alias!(%{version_num: "7.0", version_name: "seven:v1"})}
  end

  describe "changeset" do
    test "accepts the known products, plans and billing intervals", %{version_alias: row} do
      for product <- VersionPlanAccess.products(),
          plan <- VersionPlanAccess.plans(),
          interval <- VersionPlanAccess.billing_intervals() do
        assert changeset(row, %{product: product, plan: plan, billing_interval: interval}).valid?
      end

      assert %{product: ["is invalid"]} =
               errors_on(changeset(row, %{product: "SANSHEETS", plan: "PRO"}))

      assert %{plan: ["is invalid"]} =
               errors_on(changeset(row, %{product: "SANAPI", plan: "BUSINES_MAX"}))

      assert %{billing_interval: ["is invalid"]} =
               errors_on(
                 changeset(row, %{product: "SANAPI", plan: "PRO", billing_interval: "week"})
               )
    end

    test "the plan name is upcased", %{version_alias: row} do
      changeset = changeset(row, %{product: "SANAPI", plan: " business_max "})

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :plan) == "BUSINESS_MAX"
    end

    test "a plan has access to a version once per billing interval", %{version_alias: row} do
      assert {:ok, _} = insert(row, %{product: "SANAPI", plan: "BUSINESS_MAX"})

      assert {:ok, _} =
               insert(row, %{product: "SANAPI", plan: "BUSINESS_MAX", billing_interval: "year"})

      assert {:error, changeset} = insert(row, %{product: "SANAPI", plan: "BUSINESS_MAX"})
      assert %{plan: ["already has access to this version"]} = errors_on(changeset)
    end

    test "is rejected for a product the version is not exposed in" do
      row = create_alias!(%{version_num: "8.0", version_name: "eight:v1", exposed_in: "api_only"})

      assert changeset(row, %{product: "SANAPI", plan: "PRO"}).valid?

      assert %{product: ["eight:v1 is not exposed in SANBASE (exposed_in: api_only)"]} =
               errors_on(changeset(row, %{product: "SANBASE", plan: "PRO"}))
    end
  end

  describe "matches?" do
    test "the product, the plan, the billing interval and the trial" do
      row = %VersionPlanAccess{
        product: "SANAPI",
        plan: "BUSINESS_MAX",
        billing_interval: "year",
        accessible_if_trial: false
      }

      assert VersionPlanAccess.matches?(row, "SANAPI", "BUSINESS_MAX", "year", false)

      refute VersionPlanAccess.matches?(row, "SANBASE", "BUSINESS_MAX", "year", false)
      refute VersionPlanAccess.matches?(row, "SANAPI", "BUSINESS_PRO", "year", false)
      refute VersionPlanAccess.matches?(row, "SANAPI", "BUSINESS_MAX", "month", false)
      refute VersionPlanAccess.matches?(row, "SANAPI", "BUSINESS_MAX", "year", true)
    end

    test "ANY matches every plan, also no subscription" do
      row = %VersionPlanAccess{
        product: "SANAPI",
        plan: "ANY",
        billing_interval: "any",
        accessible_if_trial: true
      }

      for plan <- ["FREE", "PRO", "BUSINESS_MAX"], interval <- [nil, "month", "year"] do
        assert VersionPlanAccess.matches?(row, "SANAPI", plan, interval, false)
      end
    end
  end

  defp changeset(row, attrs),
    do:
      VersionPlanAccess.changeset(%VersionPlanAccess{}, Map.put(attrs, :version_alias_id, row.id))

  defp insert(row, attrs), do: row |> changeset(attrs) |> Repo.insert()
end
