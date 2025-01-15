defmodule Sanbase.MetricRegistrySyncTest do
  use SanbaseWeb.ConnCase
  alias Sanbase.Metric.Registry

  @moduletag capture_log: true

  test "syncing", _context do
    [m1_id, m2_id] = create_sync_requirements()

    {:ok, m1} = Registry.by_id(m1_id)
    {:ok, m2} = Registry.by_id(m2_id)

    assert m1.sync_status == "not_synced"
    assert m2.sync_status == "not_synced"

    assert {:ok, %{status: "executing", uuid: uuid}} = Registry.Sync.sync([m1_id, m2_id])

    Process.sleep(100)

    assert {:ok, %{status: "completed", uuid: ^uuid}} = Registry.Sync.by_uuid(uuid)
    {:ok, m1} = Registry.by_id(m1_id)
    {:ok, m2} = Registry.by_id(m2_id)
    assert m1.sync_status == "synced"
    assert m2.sync_status == "synced"
  end

  defp create_sync_requirements() do
    # Get 3 records
    {:ok, m1} = Registry.by_name("price_usd_5m")
    {:ok, m2} = Registry.by_name("mvrv_usd")
    {:ok, m3} = Registry.by_name("social_volume_total")

    # Create change suggestions
    {:ok, ch1} =
      Registry.ChangeSuggestion.create_change_suggestion(
        m1,
        %{"min_interval" => "5m"},
        "for tests",
        "ivan@santiment.net"
      )

    {:ok, _unused} =
      Registry.ChangeSuggestion.create_change_suggestion(
        m1,
        %{"min_interval" => "10m"},
        "for tests",
        "ivan@santiment.net"
      )

    {:ok, ch2} =
      Registry.ChangeSuggestion.create_change_suggestion(
        m2,
        %{"min_interval" => "5m"},
        "for tests",
        "ivan@santiment.net"
      )

    {:ok, ch3} =
      Registry.ChangeSuggestion.create_change_suggestion(
        m2,
        %{"aliases" => [%{name: "mvrv_usd_new_alias"}]},
        "for tests",
        "ivan@santiment.net"
      )

    {:ok, ch4} =
      Registry.ChangeSuggestion.create_change_suggestion(
        m1,
        %{"aliases" => [%{name: "price_usd_gap_filled"}]},
        "for tests",
        "ivan@santiment.net"
      )

    {:ok, ch5} =
      Registry.ChangeSuggestion.create_change_suggestion(
        m3,
        %{"min_interval" => "2h"},
        "for tests",
        "ivan@santiment.net"
      )

    # Approve all 4 suggestions
    {:ok, _} = Registry.ChangeSuggestion.update_status(ch1.id, "approved")
    {:ok, _} = Registry.ChangeSuggestion.update_status(ch2.id, "approved")
    {:ok, _} = Registry.ChangeSuggestion.update_status(ch3.id, "approved")
    {:ok, _} = Registry.ChangeSuggestion.update_status(ch4.id, "approved")
    {:ok, _} = Registry.ChangeSuggestion.update_status(ch5.id, "approved")

    # Verify only price_usd_5m and mvrv_usd metrics to properly test
    # that sync only affects verified metrics
    {:ok, _} = Sanbase.Metric.Registry.update(m1, %{is_verified: true}, emit_event: false)

    {:ok, _} = Sanbase.Metric.Registry.update(m2, %{is_verified: true}, emit_event: false)

    [m1.id, m2.id]
  end
end
