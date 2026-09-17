defmodule Sanbase.Metric.VersionAliasTest do
  use Sanbase.DataCase, async: false

  import Sanbase.MetricVersionAliasHelpers, only: [create_alias!: 1]

  alias Sanbase.Repo
  alias Sanbase.Metric.VersionAlias

  @metric "daily_active_addresses"

  setup do
    VersionAlias.clear_cache()
    :ok
  end

  # The version numbers below (7.x) are not touched by the seed migration, so the
  # assertions hold with or without the seeded rows in the database.

  describe "changeset" do
    test "names must look like aliases and versions must not" do
      assert %{version_name: [error]} =
               errors_on(changeset(%{version_num: "7.0", version_name: "Seven-PIT"}))

      assert error =~ "must look like"

      assert %{version_num: ["looks like an alias name, not a version"]} =
               errors_on(changeset(%{version_num: "seven", version_name: "seven:v1"}))

      # Versions are free-form otherwise, the Experimental one included.
      assert changeset(%{version_num: "Experimental (Weighted Age)", version_name: "exp"}).valid?
    end

    test "only the global scope exists for now" do
      assert changeset(%{version_num: "7.0", version_name: "seven:v1"}).valid?
      assert changeset(%{scope: "global", version_num: "7.0", version_name: "seven:v1"}).valid?

      assert %{scope: ["is invalid"]} =
               errors_on(
                 changeset(%{scope: "category", version_num: "7.0", version_name: "s:v1"})
               )
    end

    test "both fields are required, also when cleared in the edit form" do
      assert %{version_num: ["can't be blank"], version_name: ["can't be blank"]} =
               errors_on(changeset(%{}))

      row = create_alias!(%{version_num: "7.0", version_name: "seven:v1"})

      # Ecto casts "" to nil; against an existing value that is a change to nil.
      assert %{version_name: ["can't be blank"]} =
               errors_on(VersionAlias.changeset(row, %{version_name: "  "}))
    end

    test "a version has one name and a name belongs to one version" do
      create_alias!(%{version_num: "7.0", version_name: "seven:v1"})

      assert {:error, changeset} = insert(%{version_num: "7.0", version_name: "other:v1"})
      assert %{version_num: ["already has a name"]} = errors_on(changeset)

      assert {:error, changeset} = insert(%{version_num: "7.1", version_name: "seven:v1"})
      assert %{version_name: ["is already the name of another version"]} = errors_on(changeset)
    end
  end

  describe "resolution" do
    test "a row names the version for every metric, both ways" do
      create_alias!(%{version_num: "7.0", version_name: "seven:v1", description: "Seven"})

      assert [
               %{
                 version: "7.0",
                 version_num: "7.0",
                 version_name: "seven:v1",
                 description: "Seven"
               }
             ] = VersionAlias.to_maps(["7.0"])

      assert {:ok, "7.0"} == VersionAlias.to_version_num(@metric, "seven:v1")
      assert {:ok, "7.0"} == VersionAlias.to_version_num("price_usd", "seven:v1")
    end

    test "versions without a row fall back to the number and pass through as input" do
      assert [%{version_num: "7.9", version_name: "7.9", description: nil}] =
               VersionAlias.to_maps(["7.9"])

      assert {:ok, "7.9"} == VersionAlias.to_version_num(@metric, "7.9")

      assert {:ok, "Experimental (Weighted Age)"} ==
               VersionAlias.to_version_num(@metric, "Experimental (Weighted Age)")
    end

    test "a real version that happens to look like a name still passes through" do
      Sanbase.Mock.prepare_mock2(&Sanbase.Metric.available_versions/1, {:ok, ["1.0", "beta"]})
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, "beta"} == VersionAlias.to_version_num(@metric, "beta")
        assert {:error, error} = VersionAlias.to_version_num(@metric, "latest")
        assert error =~ "is not a version name"
      end)
    end

    test "an unknown name is an error listing the known names" do
      create_alias!(%{version_num: "7.0", version_name: "seven:v1"})

      assert {:error, error} = VersionAlias.to_version_num(@metric, "nope_pit:v9")
      assert error =~ ~s("nope_pit:v9" is not a version name of #{@metric})
      assert error =~ "seven:v1"
    end

    test "rows are cached until clear_cache/0" do
      assert [%{version_name: "7.0"}] = VersionAlias.to_maps(["7.0"])

      Repo.insert!(%VersionAlias{version_num: "7.0", version_name: "seven:v1"})

      assert [%{version_name: "7.0"}] = VersionAlias.to_maps(["7.0"])

      VersionAlias.clear_cache()

      assert [%{version_name: "seven:v1"}] = VersionAlias.to_maps(["7.0"])
    end
  end

  defp changeset(attrs), do: VersionAlias.changeset(%VersionAlias{}, attrs)

  defp insert(attrs), do: attrs |> changeset() |> Repo.insert()
end
