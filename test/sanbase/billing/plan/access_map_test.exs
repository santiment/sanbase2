defmodule Sanbase.Billing.Plan.AccessMapTest do
  @moduledoc ~s"""
  Tests the allow-list rules shared by custom plans and bundles.

  The important property is that the two ways of asking agree: `allows?/2`
  answers for one item without building a list, and `resolve/2` builds the whole
  list. If they ever disagree, a customer's access depends on which function
  happened to be called, which is the kind of bug that shows up as "it works in
  the metric list but 403s on the actual call".
  """

  use ExUnit.Case, async: true

  alias Sanbase.Billing.Plan.AccessMap

  @all [
    "price_usd",
    "volume_usd",
    "social_volume_total",
    "social_dominance",
    "mvrv_usd",
    "dev_activity"
  ]

  defp all, do: fn -> @all end

  describe "resolve/2" do
    test "an explicit list is taken as is" do
      map = %{"accessible" => ["price_usd", "mvrv_usd"]}
      assert AccessMap.resolve(map, all()) |> Enum.sort() == ["mvrv_usd", "price_usd"]
    end

    test "\"all\" means every known item" do
      assert AccessMap.resolve(%{"accessible" => "all"}, all()) == @all
    end

    test "patterns add to the explicit list" do
      map = %{"accessible" => ["price_usd"], "accessible_patterns" => ["^social_"]}

      assert AccessMap.resolve(map, all()) |> Enum.sort() ==
               ["price_usd", "social_dominance", "social_volume_total"]
    end

    test "not_accessible wins over accessible" do
      map = %{"accessible" => "all", "not_accessible" => ["mvrv_usd"]}
      refute "mvrv_usd" in AccessMap.resolve(map, all())
    end

    test "not_accessible_patterns win over accessible" do
      map = %{"accessible" => "all", "not_accessible_patterns" => ["^social_"]}
      resolved = AccessMap.resolve(map, all())

      refute "social_volume_total" in resolved
      refute "social_dominance" in resolved
      assert "price_usd" in resolved
    end

    test "an empty or nil map allows nothing" do
      assert AccessMap.resolve(%{}, all()) == []
      assert AccessMap.resolve(nil, all()) == []
    end
  end

  describe "allows?/2 agrees with resolve/2" do
    # Every shape the maps can take, checked item by item against the list.
    @maps [
      %{"accessible" => "all"},
      %{"accessible" => []},
      %{"accessible" => ["price_usd", "mvrv_usd"]},
      %{"accessible" => ["price_usd"], "accessible_patterns" => ["^social_"]},
      %{"accessible" => "all", "not_accessible" => ["mvrv_usd"]},
      %{"accessible" => "all", "not_accessible_patterns" => ["^social_"]},
      %{
        "accessible" => "all",
        "not_accessible" => ["price_usd"],
        "not_accessible_patterns" => ["^dev_"]
      },
      %{
        "accessible" => ["price_usd"],
        "accessible_patterns" => ["^social_"],
        "not_accessible_patterns" => ["_dominance$"]
      },
      %{"accessible" => "all", "not_accessible" => "all"},
      %{}
    ]

    test "for every map shape and every known item" do
      for map <- @maps do
        resolved = AccessMap.resolve(map, all())

        for item <- @all do
          assert AccessMap.allows?(map, item) == item in resolved,
                 """
                 allows?/2 and resolve/2 disagree.

                   map:      #{inspect(map)}
                   item:     #{inspect(item)}
                   allows?:  #{inspect(AccessMap.allows?(map, item))}
                   in list:  #{inspect(item in resolved)}
                 """
        end
      end
    end

    test "nil map allows nothing" do
      refute AccessMap.allows?(nil, "price_usd")
    end
  end
end
