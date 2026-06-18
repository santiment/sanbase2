defmodule Sanbase.NonCryptoAssetTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.NonCryptoAsset
  alias Sanbase.Project.SourceSlugMapping

  describe "create/1" do
    test "with valid attributes" do
      assert {:ok, asset} =
               NonCryptoAsset.create(%{
                 slug: "gold",
                 name: "Gold",
                 ticker: "XAU",
                 asset_type: :commodity
               })

      assert asset.slug == "gold"
      assert asset.asset_type == :commodity
    end

    test "missing required fields" do
      assert {:error, changeset} = NonCryptoAsset.create(%{ticker: "XAU"})

      errors = errors_on(changeset)
      assert %{slug: _, name: _, asset_type: _} = errors
    end

    test "duplicate slug" do
      insert(:non_crypto_asset, slug: "gold")

      assert {:error, changeset} =
               NonCryptoAsset.create(%{slug: "gold", name: "Gold", asset_type: :commodity})

      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end

    test "slug colliding with a project slug" do
      insert(:random_project, slug: "santiment")

      assert {:error, changeset} =
               NonCryptoAsset.create(%{slug: "santiment", name: "X", asset_type: :other})

      assert %{slug: ["already used by a project"]} = errors_on(changeset)
    end

    test "project slug colliding with a non-crypto asset slug is rejected" do
      insert(:non_crypto_asset, slug: "gold")

      changeset =
        Sanbase.Project.changeset(%Sanbase.Project{}, %{name: "Gold", slug: "gold"})

      assert %{slug: ["already used by a non-crypto asset"]} = errors_on(changeset)
    end

    test "hiding sets hidden_since, unhiding clears it" do
      assert {:ok, asset} =
               NonCryptoAsset.create(%{
                 slug: "gold",
                 name: "Gold",
                 asset_type: :commodity,
                 is_hidden: true
               })

      assert %DateTime{} = asset.hidden_since

      assert {:ok, asset} =
               NonCryptoAsset.changeset(asset, %{is_hidden: false}) |> Sanbase.Repo.update()

      refute asset.is_hidden
      assert is_nil(asset.hidden_since)
    end
  end

  describe "list/1 and slugs/0" do
    setup do
      gold = insert(:non_crypto_asset, slug: "gold", name: "Gold", asset_type: :commodity)
      sp500 = insert(:non_crypto_asset, slug: "sp500", name: "S&P 500", asset_type: :index)

      hidden =
        insert(:non_crypto_asset, slug: "hidden-asset", name: "Hidden", is_hidden: true)

      %{gold: gold, sp500: sp500, hidden: hidden}
    end

    test "list excludes hidden assets by default", context do
      slugs = NonCryptoAsset.list() |> Enum.map(& &1.slug)

      assert context.gold.slug in slugs
      assert context.sp500.slug in slugs
      refute context.hidden.slug in slugs
    end

    test "list includes hidden assets when asked", context do
      slugs = NonCryptoAsset.list(include_hidden: true) |> Enum.map(& &1.slug)
      assert context.hidden.slug in slugs
    end

    test "list filters by asset type", context do
      assert [%{slug: slug}] = NonCryptoAsset.list(asset_type: :index)
      assert slug == context.sp500.slug
    end

    test "slugs returns visible slugs", context do
      slugs = NonCryptoAsset.slugs()

      assert context.gold.slug in slugs
      refute context.hidden.slug in slugs
    end
  end

  describe "source slug mappings" do
    test "create mapping pointing to a non-crypto asset" do
      asset = insert(:non_crypto_asset, slug: "gold")

      assert {:ok, _} =
               SourceSlugMapping.create(%{
                 source: "hyperliquid",
                 slug: "GOLD",
                 non_crypto_asset_id: asset.id
               })

      assert {"GOLD", "gold"} in SourceSlugMapping.get_source_slug_mappings("hyperliquid",
               return: :all
             )

      assert SourceSlugMapping.get_source_slug("gold", "hyperliquid") == "GOLD"
    end

    test "mapping must reference exactly one of project/non-crypto asset" do
      asset = insert(:non_crypto_asset)
      project = insert(:random_project)

      assert {:error, changeset} =
               SourceSlugMapping.create(%{source: "hyperliquid", slug: "GOLD"})

      assert %{project_id: ["either project or non-crypto asset must be set"]} =
               errors_on(changeset)

      assert {:error, changeset} =
               SourceSlugMapping.create(%{
                 source: "hyperliquid",
                 slug: "GOLD",
                 project_id: project.id,
                 non_crypto_asset_id: asset.id
               })

      assert %{project_id: ["cannot set both project and non-crypto asset"]} =
               errors_on(changeset)
    end

    test "get_source_slug_mappings filters by the :return option" do
      asset = insert(:non_crypto_asset, slug: "gold")
      project = insert(:random_project, slug: "bitcoin")

      {:ok, _} =
        SourceSlugMapping.create(%{
          source: "hyperliquid",
          slug: "GOLD",
          non_crypto_asset_id: asset.id
        })

      {:ok, _} =
        SourceSlugMapping.create(%{
          source: "hyperliquid",
          slug: "BTC",
          project_id: project.id
        })

      # Default is crypto-project-only.
      default = SourceSlugMapping.get_source_slug_mappings("hyperliquid")
      assert {"BTC", "bitcoin"} in default
      refute {"GOLD", "gold"} in default

      crypto =
        SourceSlugMapping.get_source_slug_mappings("hyperliquid", return: :crypto_project_only)

      assert crypto == default

      non_crypto =
        SourceSlugMapping.get_source_slug_mappings("hyperliquid",
          return: :non_crypto_project_only
        )

      assert {"GOLD", "gold"} in non_crypto
      refute {"BTC", "bitcoin"} in non_crypto

      all = SourceSlugMapping.get_source_slug_mappings("hyperliquid", return: :all)
      assert {"GOLD", "gold"} in all
      assert {"BTC", "bitcoin"} in all
    end
  end
end
