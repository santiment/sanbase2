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

    test "the scope is global by default, and must be a known scope" do
      assert changeset(%{version_num: "7.0", version_name: "seven:v1"}).valid?
      assert changeset(%{scope: "global", version_num: "7.0", version_name: "seven:v1"}).valid?
      assert changeset(%{scope: "github", version_num: "7.0", version_name: "seven:v1"}).valid?
      assert changeset(%{scope: "social", version_num: "7.0", version_name: "seven:v1"}).valid?

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

    test "a scope's own rows override the global ones" do
      create_alias!(%{version_num: "2.0", version_name: "modern:v1"})
      create_alias!(%{scope: "github", version_num: "2.0", version_name: "filtered:v1"})

      assert [%{version_name: "modern:v1"}] = VersionAlias.to_maps(["2.0"])
      assert [%{version_name: "filtered:v1"}] = VersionAlias.to_maps(["2.0"], "github")
      assert VersionAlias.to_version_name("2.0", "github") == "filtered:v1"
      assert VersionAlias.version_nums("github") == ["2.0"]

      assert {:ok, "2.0"} == VersionAlias.to_version_num("filtered:v1", "github")
      assert {:error, error} = VersionAlias.to_version_num("modern:v1", "github")
      assert error =~ "filtered:v1"
      refute error =~ "modern:v1."
      assert {:error, _} = VersionAlias.to_version_num("filtered:v1")
    end

    test "every scope sees the global rows" do
      create_alias!(%{version_num: "1.0", version_name: "original:v1"})
      create_alias!(%{scope: "social", version_num: "2.0", version_name: "modern:v1"})

      for scope <- ["github", "social"] do
        assert VersionAlias.to_version_name("1.0", scope) == "original:v1"
        assert {:ok, "1.0"} == VersionAlias.to_version_num("original:v1", scope)
      end

      assert Enum.sort(VersionAlias.version_nums("social")) == ["1.0", "2.0"]
      assert VersionAlias.version_nums("github") == ["1.0"]
      assert VersionAlias.version_nums() == ["1.0"]
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
