defmodule Sanbase.AvailableSlugsTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.AvailableSlugs

  # The GenServer is not started in the test env, so fill the table by hand to
  # exercise the ETS lookups. The table dies together with the test process.
  @ets_table :available_projects_slugs_ets_table

  setup do
    table = :ets.new(@ets_table, [:set, :protected, :named_table, read_concurrency: true])

    :ets.insert(table, {"micron", :non_crypto_asset})
    :ets.insert(table, {"bitcoin", :project})
    :ets.insert(table, {"total_market", :group_of_slugs})

    :ok
  end

  describe "non_crypto_asset_slug?/1" do
    test "true only for the non-crypto assets" do
      assert AvailableSlugs.non_crypto_asset_slug?("micron")

      refute AvailableSlugs.non_crypto_asset_slug?("bitcoin")
      refute AvailableSlugs.non_crypto_asset_slug?("total_market")
      refute AvailableSlugs.non_crypto_asset_slug?("not-a-slug")
    end
  end

  describe "valid_slug?/1" do
    test "true for every kind of slug in the table" do
      assert AvailableSlugs.valid_slug?("micron")
      assert AvailableSlugs.valid_slug?("bitcoin")
      assert AvailableSlugs.valid_slug?("total_market")
    end

    test "false for a slug that is not in the table" do
      refute AvailableSlugs.valid_slug?("not-a-slug")
    end

    test "true for the group of slugs that are not in the table" do
      assert AvailableSlugs.valid_slug?("TOTAL_ERC20")
    end
  end
end
