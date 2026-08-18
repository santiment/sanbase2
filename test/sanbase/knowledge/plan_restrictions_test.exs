defmodule Sanbase.Knowledge.PlanRestrictionsTest do
  use ExUnit.Case, async: true

  alias Sanbase.Billing.Plan.ApiAccessChecker
  alias Sanbase.Knowledge.PlanRestrictions

  describe "list_rows/0" do
    # Hardcoded so a plan change breaks this and forces a re-read of the prompt
    # text. Note Sanbase BASIC / PRO get the FREE window, unlike their namesakes.
    test "lists every plan with the limits the access checker currently grants" do
      limits =
        Enum.map(
          PlanRestrictions.list_rows(),
          &{&1.subscription_product, &1.plan, &1.historical_data_in_days,
           &1.realtime_data_cut_off_in_days}
        )

      assert limits == [
               {"SANAPI", "FREE", 365, 30},
               {"SANAPI", "BASIC", 365, 0},
               {"SANAPI", "PRO", nil, 0},
               {"SANAPI", "BUSINESS_PRO", 730, 0},
               {"SANAPI", "BUSINESS_MAX", nil, 0},
               {"SANAPI", "INSTITUTIONAL", 1095, 0},
               {"SANAPI", "ENTERPRISE", nil, 0},
               {"SANBASE", "BASIC", 365, 30},
               {"SANBASE", "PRO", 365, 30},
               {"SANBASE", "PRO_PLUS", 730, 0},
               {"SANBASE", "MAX", 730, 0}
             ]
    end

    # A row for these would be a wrong answer, not a missing one: CUSTOM resolves
    # per contract, and SanAPI PRO_PLUS / MAX are not sold.
    test "omits per-contract plans and product/plan pairs that are not sold" do
      pairs = Enum.map(PlanRestrictions.list_rows(), &{&1.subscription_product, &1.plan})

      refute {"SANAPI", "CUSTOM"} in pairs
      refute {"SANAPI", "PRO_PLUS"} in pairs
      refute {"SANAPI", "MAX"} in pairs
    end
  end

  describe "render_inner_section/0" do
    setup do
      %{section: PlanRestrictions.render_inner_section()}
    end

    test "returns the body only, leaving the tags to the call site", %{section: section} do
      refute section =~ "<SanAPI_Data_Access_Restrictions>"
      refute section =~ "</SanAPI_Data_Access_Restrictions>"
    end

    test "renders one table row per listed plan", %{section: section} do
      for row <- PlanRestrictions.list_rows() do
        assert section =~ "| #{row.label} |"
      end
    end

    # The signature a reported symptom is matched against — the point of the block.
    test "spells out the FREE-tier diagnostic signature", %{section: section} do
      assert ApiAccessChecker.historical_data_in_days("SANAPI", "FREE") == 365
      assert ApiAccessChecker.realtime_data_cut_off_in_days("SANAPI", "FREE") == 30

      assert section =~ "335 d wide: from 365 d ago to 30 d ago"
      assert section =~ "roughly 335 days wide"
      assert section =~ "roughly 30 days before today"
      assert section =~ "FREE-tier signature"
    end

    test "renders an unlimited history as words, never as a blank or nil", %{section: section} do
      assert ApiAccessChecker.historical_data_in_days("SANAPI", "BUSINESS_MAX") == nil

      assert section =~ "| SanAPI BUSINESS_MAX | unlimited | none | full history, up to now |"
      refute section =~ "nil"
      refute section =~ "||"
    end

    # Explains full history on some metrics and a clipped window on others.
    test "states that freely available metrics escape both limits", %{section: section} do
      assert section =~ "exempt from BOTH limits"
    end

    test "tells the model to prefer these numbers over retrieved prose", %{section: section} do
      assert section =~ "THIS is correct"
    end

    test "names per-contract plans as a lookup rather than guessing a window", %{section: section} do
      assert section =~ "CUSTOM, bundle and package-based plans"
    end

    # Raise this consciously, not by accident.
    test "stays a small fraction of the prompt", %{section: section} do
      assert byte_size(section) < 3_200
    end
  end
end
