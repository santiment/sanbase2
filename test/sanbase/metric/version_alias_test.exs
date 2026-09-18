defmodule Sanbase.Metric.VersionAliasTest do
  use Sanbase.DataCase, async: false

  import Sanbase.MetricVersionAliasHelpers, only: [create_alias!: 1]

  alias Sanbase.Repo
  alias Sanbase.Metric.VersionAlias

  setup do
    VersionAlias.clear_cache()
    :ok
  end

  describe "changeset" do
    test "names end in :vN and versions never look like names" do
      for bad <- ["Seven-PIT", "seven", "seven:1", "seven:v", "7.0"] do
        assert %{version_name: [error]} =
                 errors_on(changeset(%{version_num: "7.0", version_name: bad}))

        assert error =~ "must look like", bad
      end

      for good <- ["seven:v1", "seven_pit:v1.2", "s7:v10"] do
        assert changeset(%{version_num: "7.0", version_name: good}).valid?, good
      end

      assert %{version_num: ["looks like a name, not a version"]} =
               errors_on(changeset(%{version_num: "seven:v1", version_name: "other:v1"}))

      assert changeset(%{version_num: "Experimental (Weighted Age)", version_name: "exp:v1"}).valid?
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
    test "a row names the version, both ways" do
      create_alias!(%{version_num: "7.0", version_name: "seven:v1", description: "Seven"})

      assert [
               %{
                 version: "7.0",
                 version_num: "7.0",
                 version_name: "seven:v1",
                 description: "Seven"
               }
             ] =
               VersionAlias.to_maps(["7.0"])

      assert {:ok, "7.0"} == VersionAlias.to_version_num("seven:v1")
    end

    test "anything not shaped like a name passes through and falls back to itself" do
      assert [%{version_num: "7.9", version_name: "7.9", description: nil}] =
               VersionAlias.to_maps(["7.9"])

      for version <- ["7.9", "Experimental (Weighted Age)", "beta", "latest", "v2"] do
        assert {:ok, version} == VersionAlias.to_version_num(version)
      end
    end

    test "an unknown name is an error listing the known names" do
      create_alias!(%{version_num: "7.0", version_name: "seven:v1"})

      assert {:error, error} = VersionAlias.to_version_num("nope_pit:v9")
      assert error =~ ~s("nope_pit:v9" is not a known version name)
      assert error =~ "seven:v1"
    end

    test "seed_defaults/0 inserts the default rows once" do
      :ok = VersionAlias.seed_defaults()
      count = Repo.aggregate(VersionAlias, :count)

      :ok = VersionAlias.seed_defaults()
      assert Repo.aggregate(VersionAlias, :count) == count

      assert {:ok, "2.1"} == VersionAlias.to_version_num("modern_pit:v1")
      assert [%{version_name: "original:v1"}] = VersionAlias.to_maps(["1.0"])
    end

    test "seed_defaults/0 skips a default whose name is already taken by another version" do
      Repo.delete_all(from(a in VersionAlias, where: a.version_num == "2.0"))
      create_alias!(%{version_num: "7.0", version_name: "modern:v1"})

      :ok = VersionAlias.seed_defaults()

      assert Repo.get_by(VersionAlias, version_num: "2.0") == nil
      assert {:ok, "7.0"} == VersionAlias.to_version_num("modern:v1")
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
