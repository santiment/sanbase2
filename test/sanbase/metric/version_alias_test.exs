defmodule Sanbase.Metric.VersionAliasTest do
  use Sanbase.DataCase, async: false

  import Sanbase.MetricVersionAliasHelpers, only: [create_alias!: 1, create_category!: 1]

  alias Sanbase.Repo
  alias Sanbase.Metric.Category
  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.VersionAlias

  # A real metric, so metric-scoped rows pass the "known metric" validation.
  @metric "daily_active_addresses"
  # A metric the tests never put in a category.
  @other_metric "price_usd"

  setup do
    VersionAlias.clear_cache()
    Category.Cache.clear()
    :ok
  end

  # The version numbers below (7.x) are not touched by the seed migration, so the
  # assertions hold with or without the seeded global rows in the database.

  describe "changeset" do
    test "global rows carry no category and an empty scope value" do
      changeset = changeset(%{scope_type: "global", version_num: "7.0", version_name: "seven:v1"})
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :scope_value) == ""

      assert %{category_id: [error]} =
               errors_on(changeset(%{scope_type: "global", category_id: 1, version_num: "7.0"}))

      assert error =~ "must be empty"
    end

    test "category rows require a category" do
      assert %{category_id: ["is required for category scope"]} =
               errors_on(changeset(%{scope_type: "category", version_num: "7.0"}))
    end

    test "metric rows require a known metric" do
      assert %{scope_value: ["is required for metric scope"]} =
               errors_on(changeset(%{scope_type: "metric", version_num: "7.0"}))

      assert %{scope_value: ["is not a known metric"]} =
               errors_on(
                 changeset(%{
                   scope_type: "metric",
                   scope_value: "no_such_metric",
                   version_num: "7.0"
                 })
               )

      assert changeset(%{scope_type: "metric", scope_value: @metric, version_num: "7.0"}).valid?
    end

    test "names must look like aliases and versions must not" do
      assert %{version_name: [error]} =
               errors_on(
                 changeset(%{scope_type: "global", version_num: "7.0", version_name: "Seven-PIT"})
               )

      assert error =~ "must look like"

      assert %{version_num: ["looks like an alias name, not a version"]} =
               errors_on(
                 changeset(%{
                   scope_type: "global",
                   version_num: "seven",
                   version_name: "seven:v1"
                 })
               )

      # Versions are free-form otherwise, the Experimental one included.
      assert changeset(%{scope_type: "global", version_num: "Experimental (Weighted Age)"}).valid?
    end

    test "a blank name becomes NULL, which is a valid shadow row" do
      changeset = changeset(%{scope_type: "global", version_num: "7.0", version_name: "  "})
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :version_name) == nil
    end

    test "a name already given to a different version of the same metrics is rejected" do
      category = create_category!("VA Collision")
      create_alias!(%{scope_type: "global", version_num: "7.0", version_name: "seven:v1"})

      assert %{version_name: [error]} =
               errors_on(
                 changeset(%{
                   scope_type: "category",
                   category_id: category.id,
                   version_num: "7.1",
                   version_name: "seven:v1"
                 })
               )

      assert error =~ "already the name of version 7.0"

      # The same name for the same version in a narrower scope is fine (a plain override).
      assert changeset(%{
               scope_type: "category",
               category_id: category.id,
               version_num: "7.0",
               version_name: "seven:v1"
             }).valid?
    end

    test "clearing a field in the edit form does not crash: blank name shadows, blank version errors" do
      row = create_alias!(%{scope_type: "global", version_num: "7.0", version_name: "seven:v1"})

      # Ecto casts "" to nil; against an existing value that is a change to nil.
      cleared_name = VersionAlias.changeset(row, %{version_name: ""})
      assert cleared_name.valid?
      assert Ecto.Changeset.get_field(cleared_name, :version_name) == nil

      assert %{version_num: ["can't be blank"]} =
               errors_on(VersionAlias.changeset(row, %{version_num: ""}))
    end

    test "priority is only accepted on category rows" do
      assert %{priority: ["only applies to category scope"]} =
               errors_on(changeset(%{scope_type: "global", version_num: "7.0", priority: 5}))

      assert %{priority: ["only applies to category scope"]} =
               errors_on(
                 changeset(%{
                   scope_type: "metric",
                   scope_value: @metric,
                   version_num: "7.0",
                   priority: 5
                 })
               )

      category = create_category!("VA Priority")

      assert changeset(%{
               scope_type: "category",
               category_id: category.id,
               version_num: "7.0",
               priority: 5
             }).valid?
    end

    test "duplicate rows in one scope are rejected by the database" do
      create_alias!(%{scope_type: "global", version_num: "7.0", version_name: "seven:v1"})

      assert {:error, changeset} =
               %VersionAlias{}
               |> VersionAlias.changeset(%{
                 scope_type: "global",
                 version_num: "7.0",
                 version_name: "other:v1"
               })
               |> Repo.insert()

      assert %{version_num: ["already has an alias in this scope"]} = errors_on(changeset)
    end
  end

  describe "resolution" do
    test "a global row names the version for every metric, both ways" do
      create_alias!(%{
        scope_type: "global",
        version_num: "7.0",
        version_name: "seven:v1",
        description: "Seven"
      })

      assert [
               %{
                 version: "7.0",
                 version_num: "7.0",
                 version_name: "seven:v1",
                 description: "Seven"
               }
             ] =
               VersionAlias.to_maps(@metric, ["7.0"])

      assert {:ok, "7.0"} == VersionAlias.to_version_num(@metric, "seven:v1")
      assert {:ok, "7.0"} == VersionAlias.to_version_num(@other_metric, "seven:v1")
    end

    test "versions without a row fall back to the number and pass through as input" do
      assert [%{version_num: "7.9", version_name: "7.9", description: nil}] =
               VersionAlias.to_maps(@metric, ["7.9"])

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
      create_alias!(%{scope_type: "global", version_num: "7.0", version_name: "seven:v1"})

      assert {:error, error} = VersionAlias.to_version_num(@metric, "nope_pit:v9")
      assert error =~ ~s("nope_pit:v9" is not a version name of #{@metric})
      assert error =~ "seven:v1"
    end

    test "a category row replaces the global row for the metrics in that category" do
      category = create_category!("VA Social")
      put_in_category!(category, @metric)

      create_alias!(%{scope_type: "global", version_num: "7.1", version_name: "seven_pit:v1"})

      create_alias!(%{
        scope_type: "category",
        category_id: category.id,
        version_num: "7.1",
        version_name: "social_pit:v1"
      })

      assert [%{version_name: "social_pit:v1"}] = VersionAlias.to_maps(@metric, ["7.1"])
      assert [%{version_name: "seven_pit:v1"}] = VersionAlias.to_maps(@other_metric, ["7.1"])

      assert {:ok, "7.1"} == VersionAlias.to_version_num(@metric, "social_pit:v1")
      assert {:ok, "7.1"} == VersionAlias.to_version_num(@other_metric, "seven_pit:v1")

      # The inherited name is shadowed, not kept as a synonym.
      assert {:error, error} = VersionAlias.to_version_num(@metric, "seven_pit:v1")
      assert error =~ "is not a version name"
      assert {:error, _} = VersionAlias.to_version_num(@other_metric, "social_pit:v1")
    end

    test "a metric row replaces category and global rows" do
      category = create_category!("VA Metric Override")
      put_in_category!(category, @metric)

      create_alias!(%{scope_type: "global", version_num: "7.0", version_name: "seven:v1"})

      create_alias!(%{
        scope_type: "category",
        category_id: category.id,
        version_num: "7.0",
        version_name: "cat_seven:v1"
      })

      create_alias!(%{
        scope_type: "metric",
        scope_value: @metric,
        version_num: "7.0",
        version_name: "daa_seven:v1"
      })

      assert [%{version_name: "daa_seven:v1"}] = VersionAlias.to_maps(@metric, ["7.0"])
      assert {:ok, "7.0"} == VersionAlias.to_version_num(@metric, "daa_seven:v1")
      assert {:error, _} = VersionAlias.to_version_num(@metric, "cat_seven:v1")
    end

    test "a NULL name in a narrower scope removes the inherited alias" do
      category = create_category!("VA Shadow")
      put_in_category!(category, @metric)

      create_alias!(%{scope_type: "global", version_num: "7.0", version_name: "seven:v1"})
      create_alias!(%{scope_type: "category", category_id: category.id, version_num: "7.0"})

      assert [%{version_name: "7.0"}] = VersionAlias.to_maps(@metric, ["7.0"])
      assert {:error, _} = VersionAlias.to_version_num(@metric, "seven:v1")
      assert [%{version_name: "seven:v1"}] = VersionAlias.to_maps(@other_metric, ["7.0"])
    end

    test "a name shared by two versions is rejected as input and not advertised" do
      category = create_category!("VA Ambiguous")
      put_in_category!(category, @metric)

      create_alias!(%{scope_type: "global", version_num: "7.0", version_name: "dup:v1"})

      # Bypass the changeset's advisory check, as a concurrent write or a later
      # taxonomy change would.
      Repo.insert!(%VersionAlias{
        scope_type: "category",
        category_id: category.id,
        scope_value: "",
        version_num: "7.1",
        version_name: "dup:v1"
      })

      VersionAlias.clear_cache()

      assert {:error, error} = VersionAlias.to_version_num(@metric, "dup:v1")
      assert error =~ "names more than one version"
      assert error =~ "7.0, 7.1"

      assert [%{version_name: "7.0"}, %{version_name: "7.1"}] =
               VersionAlias.to_maps(@metric, ["7.0", "7.1"])

      # Not in the category: only the global row applies, no ambiguity.
      assert {:ok, "7.0"} == VersionAlias.to_version_num(@other_metric, "dup:v1")
    end

    test "overlapping categories: higher priority wins, then the lower category id" do
      first = create_category!("VA Overlap A")
      second = create_category!("VA Overlap B")
      put_in_category!(first, @metric)
      put_in_category!(second, @metric)

      create_alias!(%{
        scope_type: "category",
        category_id: first.id,
        version_num: "7.0",
        version_name: "a_seven:v1"
      })

      create_alias!(%{
        scope_type: "category",
        category_id: second.id,
        version_num: "7.0",
        version_name: "b_seven:v1"
      })

      assert [%{version_name: "a_seven:v1"}] = VersionAlias.to_maps(@metric, ["7.0"])

      Repo.update_all(
        from(a in VersionAlias, where: a.category_id == ^second.id),
        set: [priority: 10]
      )

      VersionAlias.clear_cache()

      assert [%{version_name: "b_seven:v1"}] = VersionAlias.to_maps(@metric, ["7.0"])
    end

    test "rows are cached until clear_cache/0" do
      assert [%{version_name: "7.0"}] = VersionAlias.to_maps(@metric, ["7.0"])

      Repo.insert!(%VersionAlias{
        scope_type: "global",
        version_num: "7.0",
        version_name: "seven:v1"
      })

      assert [%{version_name: "7.0"}] = VersionAlias.to_maps(@metric, ["7.0"])

      VersionAlias.clear_cache()

      assert [%{version_name: "seven:v1"}] = VersionAlias.to_maps(@metric, ["7.0"])
    end
  end

  defp changeset(attrs), do: VersionAlias.changeset(%VersionAlias{}, attrs)

  defp put_in_category!(category, metric) do
    {:ok, _} =
      Category.create_mapping(%{
        category_id: category.id,
        module: "Sanbase.Clickhouse.MetricAdapter",
        metric: metric
      })

    :ok
  end
end
