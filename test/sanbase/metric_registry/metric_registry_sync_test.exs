defmodule Sanbase.MetricRegistrySyncTest do
  use SanbaseWeb.ConnCase
  alias Sanbase.Metric.Registry

  @moduletag capture_log: true

  describe "dry run" do
    test "mocked sync content", _context do
      {:ok, m} = Registry.by_name("price_usd_5m")
      # Make it ready to sync.
      # Use a changeset as the update/create functrions do not allow to manually play
      # with these fields
      {:ok, m} =
        Registry.changeset(m, %{is_verified: true, sync_status: "not_synced"})
        |> Sanbase.Repo.update()

      # This is used for mock when taking the records to be synced
      # As the initiating and receiving databases in test env are the same
      # only with mocks we can ensure some changes are actually applied
      changed_m = %{
        m
        | min_interval: "1d",
          exposed_environments: "stage",
          aliases: [%Registry.Alias{name: "new_alias"}]
      }

      Sanbase.Mock.prepare_mock2(&Registry.by_ids/1, [changed_m])
      |> Sanbase.Mock.run_with_mocks(fn ->
        # Check some fields before sync
        {:ok, m} = Registry.by_id(m.id)
        assert m.sync_status == "not_synced"
        assert m.min_interval != "1d"
        assert not Enum.any?(m.aliases, &(&1.name == "new_alias"))

        # Run the Sync
        assert {:ok,
                %{
                  status: "executing",
                  uuid: uuid,
                  is_dry_run: true,
                  started_by: "test@santiment.net"
                }} =
                 Registry.Sync.sync([m.id], dry_run: true, started_by: "test@santiment.net")

        Process.sleep(1000)

        # Make sure both the outgoing and the incoming syncs are looking good
        # In test env we have both outgoing and incoming as the sync happens from and to
        # the same database.
        assert {:ok,
                %{
                  status: "completed",
                  uuid: ^uuid,
                  is_dry_run: true,
                  started_by: "test@santiment.net",
                  actual_changes: actual_changes,
                  sync_type: "outgoing"
                }} =
                 Registry.Sync.by_uuid(uuid, "outgoing")

        assert {:ok,
                %{
                  status: "completed",
                  uuid: ^uuid,
                  is_dry_run: true,
                  started_by: "test@santiment.net",
                  actual_changes: ^actual_changes,
                  sync_type: "incoming"
                }} =
                 Registry.Sync.by_uuid(uuid, "incoming")

        # The actual changes in one sync can contain many encoded {key, changes} pairs.
        # The key points to the metric. The id is not used, because by this key it should be
        # possible to fetch the record on stage and on prod, where the ids differ
        # NOTE: The changes are stored in the sync runs but they are listed as DRY RUN
        # so they are not actually applied
        assert {:ok, [{changes_key, changes_value}]} =
                 Registry.Sync.decode_changes(actual_changes)

        assert changes_key ==
                 %{data_type: "timeseries", metric: "price_usd_5m", fixed_parameters: %{}}

        assert changes_value == %{
                 aliases:
                   {:changed,
                    [{:added_to_list, 0, %Sanbase.Metric.Registry.Alias{name: "new_alias"}}]},
                 min_interval: {:changed, {:primitive_change, "1s", "1d"}},
                 exposed_environments: {:changed, {:primitive_change, "all", "stage"}}
               }

        # After dry run sync the sync status MUST NOT be synced, it should still be not_synced
        {:ok, m} = Registry.by_id(m.id)
        assert m.sync_status == "not_synced"
        assert m.min_interval != "1d"
        assert not Enum.any?(m.aliases, &(&1.name == "new_alias"))

        # No changelog was generated as no real changes were applied
        {:ok, list} = Registry.Changelog.by_metric_registry_id(m.id)
        assert [] == list
      end)
    end
  end

  describe "not dry run" do
    test "sync not_synced", _context do
      {:ok, m} = Registry.by_name("price_usd_5m")
      # Just mark it as not synced and sync.
      # This exercises the case where there are no actual changes
      assert {:ok, _} =
               Registry.changeset(m, %{sync_status: "not_synced"}) |> Sanbase.Repo.update()

      assert {:ok,
              %{
                status: "executing",
                uuid: uuid,
                is_dry_run: false,
                started_by: "test@santiment.net"
              }} =
               Registry.Sync.sync([m.id], dry_run: false, started_by: "test@santiment.net")

      Process.sleep(100)

      assert {:ok,
              %{
                status: "completed",
                uuid: ^uuid,
                is_dry_run: false,
                started_by: "test@santiment.net"
              }} = Registry.Sync.by_uuid(uuid, "incoming")

      {:ok, m} = Registry.by_id(m.id)
      assert m.sync_status == "synced"
    end

    test "syncing", _context do
      [m1_id, m2_id] = create_sync_requirements()

      {:ok, m1} = Registry.by_id(m1_id)
      {:ok, m2} = Registry.by_id(m2_id)

      assert m1.sync_status == "not_synced"
      assert m2.sync_status == "not_synced"

      assert {:ok, %{status: "executing", uuid: uuid}} =
               Registry.Sync.sync([m1_id, m2_id],
                 dry_run: false,
                 started_by: "test@santiment.net"
               )

      Process.sleep(100)

      assert {:ok,
              %{
                status: "completed",
                uuid: ^uuid,
                is_dry_run: false,
                started_by: "test@santiment.net"
              }} = Registry.Sync.by_uuid(uuid, "incoming")

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
      {:ok, _} = Sanbase.Metric.Registry.update_is_verified(m1, true)
      {:ok, _} = Sanbase.Metric.Registry.update_is_verified(m2, true)

      [m1.id, m2.id]
    end

    test "mocked sync content", _context do
      {:ok, m} = Registry.by_name("price_usd_5m")
      # Make it ready to sync.
      # Use a changeset as the update/create functrions do not allow to manually play
      # with these fields
      {:ok, m} =
        Registry.changeset(m, %{is_verified: true, sync_status: "not_synced"})
        |> Sanbase.Repo.update()

      # This is used for mock when taking the records to be synced
      # As the initiating and receiving databases in test env are the same
      # only with mocks we can ensure some changes are actually applied
      changed_m = %{
        m
        | min_interval: "1d",
          exposed_environments: "stage",
          aliases: [%Registry.Alias{name: "new_alias"}]
      }

      Sanbase.Mock.prepare_mock2(&Registry.by_ids/1, [changed_m])
      |> Sanbase.Mock.run_with_mocks(fn ->
        # Check some fields before sync
        {:ok, m} = Registry.by_id(m.id)
        assert m.sync_status == "not_synced"
        assert m.min_interval != "1d"
        assert not Enum.any?(m.aliases, &(&1.name == "new_alias"))

        # Run the Sync
        assert {:ok,
                %{
                  uuid: uuid,
                  status: "executing",
                  is_dry_run: false,
                  started_by: "test@santiment.net"
                }} =
                 Registry.Sync.sync([m.id], dry_run: false, started_by: "test@santiment.net")

        Process.sleep(200)

        # Make sure both the outgoing and the incoming syncs are looking good
        # In test env we have both outgoing and incoming as the sync happens from and to
        # the same database.
        assert {:ok,
                %{
                  status: "completed",
                  uuid: ^uuid,
                  is_dry_run: false,
                  started_by: "test@santiment.net",
                  actual_changes: actual_changes,
                  sync_type: "outgoing"
                }} =
                 Registry.Sync.by_uuid(uuid, "outgoing")

        assert {:ok,
                %{
                  status: "completed",
                  uuid: ^uuid,
                  is_dry_run: false,
                  started_by: "test@santiment.net",
                  actual_changes: ^actual_changes,
                  sync_type: "incoming"
                }} =
                 Registry.Sync.by_uuid(uuid, "incoming")

        # The actual changes in one sync can contain many encoded {key, changes} pairs.
        # The key points to the metric. The id is not used, because by this key it should be
        # possible to fetch the record on stage and on prod, where the ids differ
        assert {:ok, [{changes_key, changes_value}]} =
                 Registry.Sync.decode_changes(actual_changes)

        assert changes_key ==
                 %{data_type: "timeseries", metric: "price_usd_5m", fixed_parameters: %{}}

        assert changes_value == %{
                 aliases:
                   {:changed,
                    [{:added_to_list, 0, %Sanbase.Metric.Registry.Alias{name: "new_alias"}}]},
                 min_interval: {:changed, {:primitive_change, "1s", "1d"}},
                 exposed_environments: {:changed, {:primitive_change, "all", "stage"}}
               }

        # Check some fields after sync
        {:ok, m} = Registry.by_id(m.id)
        assert m.sync_status == "synced"
        assert m.min_interval == "1d"

        assert Enum.any?(m.aliases, &(&1.name == "new_alias"))

        # Check that the changelog records the actual sync changes for that metric
        {:ok, list} = Registry.Changelog.by_metric_registry_id(m.id)
        assert [changelog] = list

        changes =
          ExAudit.Diff.diff(
            Jason.decode!(changelog.old),
            Jason.decode!(changelog.new)
          )

        assert changes ==
                 %{
                   "aliases" => {:changed, [{:added_to_list, 0, %{"name" => "new_alias"}}]},
                   "exposed_environments" => {:changed, {:primitive_change, "all", "stage"}},
                   "min_interval" => {:changed, {:primitive_change, "1s", "1d"}}
                 }
      end)
    end
  end
end
