defmodule Sanbase.MetricRegistryDriftTest do
  use SanbaseWeb.ConnCase

  alias Sanbase.Metric.Registry
  alias Sanbase.Metric.Registry.Drift

  @moduletag capture_log: true

  test "no drift when the prod export matches the local registry", %{conn: conn} do
    body = get_export_body(conn)

    mock_remote_export(body, fn ->
      assert {:ok, result} = Drift.compute()

      assert result.missing_on_prod == []
      assert result.extra_on_prod == []
      assert result.changed == []
      assert result.local_count == result.remote_count
      assert result.identical_count == result.local_count
      assert result.local_count > 0
    end)
  end

  test "detects missing, extra and changed records", %{conn: conn} do
    # Mark one local record as not_synced so its drift is reported as pending sync
    {:ok, m} = Registry.by_name("mvrv_usd")

    {:ok, _} =
      Registry.changeset(m, %{sync_status: "not_synced"})
      |> Sanbase.Repo.update()

    remote_records =
      get_export_body(conn)
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

    # Simulate drift in the remote (prod) registry:
    # - price_usd_5m has a different min_interval on prod (manual intervention)
    # - mvrv_usd is missing on prod (not synced yet locally => pending sync)
    # - social_volume_total is missing on prod (but marked synced locally => manual)
    # - a fabricated metric exists only on prod (orphan after rename/delete on stage)
    fake_record =
      remote_records
      |> Enum.find(&(&1["metric"] == "price_usd_5m"))
      |> Map.put("metric", "metric_existing_only_on_prod")

    tampered_records =
      remote_records
      |> Enum.reject(&(&1["metric"] in ["mvrv_usd", "social_volume_total"]))
      |> Enum.map(fn
        %{"metric" => "price_usd_5m"} = map -> Map.put(map, "min_interval", "123d")
        map -> map
      end)
      |> Kernel.++([fake_record])

    tampered_body = Enum.map_join(tampered_records, "\n", &Jason.encode!/1)

    mock_remote_export(tampered_body, fn ->
      assert {:ok, result} = Drift.compute()

      # Missing on prod
      assert [missing1, missing2] = Enum.sort_by(result.missing_on_prod, & &1.key.metric)
      assert missing1.key.metric == "mvrv_usd"
      assert missing1.pending_sync? == true
      assert missing2.key.metric == "social_volume_total"
      assert missing2.pending_sync? == false

      # Extra on prod
      assert [extra] = result.extra_on_prod
      assert extra.key.metric == "metric_existing_only_on_prod"

      # Changed
      assert [changed] = result.changed
      assert changed.key.metric == "price_usd_5m"
      assert changed.pending_sync? == false

      # The diff direction is prod (old) -> stage (new)
      assert %{"min_interval" => {:changed, {:primitive_change, "123d", local_min_interval}}} =
               changed.diff

      assert local_min_interval != "123d"
    end)
  end

  test "env-local fields do not produce false positives", %{conn: conn} do
    remote_records =
      get_export_body(conn)
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

    # Tamper only with fields that are not subject to syncing
    tampered_body =
      remote_records
      |> Enum.map(fn map ->
        map
        |> Map.put("id", map["id"] + 1000)
        |> Map.put("is_verified", not map["is_verified"])
        |> Map.put("sync_status", "not_synced")
      end)
      |> Enum.map_join("\n", &Jason.encode!/1)

    mock_remote_export(tampered_body, fn ->
      assert {:ok, result} = Drift.compute()

      assert result.missing_on_prod == []
      assert result.extra_on_prod == []
      assert result.changed == []
    end)
  end

  test "legacy export format with exploded DateTime maps does not produce false positives",
       %{conn: conn} do
    record_with_deprecation = Registry.all() |> Enum.find(& &1.hard_deprecate_after)
    assert record_with_deprecation, "test requires a seeded record with hard_deprecate_after"

    dt = record_with_deprecation.hard_deprecate_after
    {microsecond, precision} = dt.microsecond

    exploded_datetime = %{
      "calendar" => "Elixir.Calendar.ISO",
      "year" => dt.year,
      "month" => dt.month,
      "day" => dt.day,
      "hour" => dt.hour,
      "minute" => dt.minute,
      "second" => dt.second,
      "microsecond" => [microsecond, precision],
      "std_offset" => 0,
      "utc_offset" => 0,
      "time_zone" => "Etc/UTC",
      "zone_abbrev" => "UTC"
    }

    tampered_body =
      get_export_body(conn)
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)
      |> Enum.map(fn
        %{"metric" => metric} = map when metric == record_with_deprecation.metric ->
          Map.put(map, "hard_deprecate_after", exploded_datetime)

        map ->
          map
      end)
      |> Enum.map_join("\n", &Jason.encode!/1)

    mock_remote_export(tampered_body, fn ->
      assert {:ok, result} = Drift.compute()

      assert result.missing_on_prod == []
      assert result.extra_on_prod == []
      assert result.changed == []
    end)
  end

  test "refuses to run on prod, where it would compare prod against itself" do
    Sanbase.Mock.prepare_mock(Sanbase.Utils.Config, :module_get, fn
      Sanbase, :deployment_env -> "prod"
      module, key -> :meck.passthrough([module, key])
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert {:error, error} = Drift.compute()
      assert error =~ "cannot be run on prod itself"
    end)
  end

  test "error when the export cannot be fetched" do
    Sanbase.Mock.prepare_mock2(&Req.get/2, {:ok, %Req.Response{status: 500, body: "error"}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert {:error, error} = Drift.compute()
      assert error =~ "Status code: 500"
    end)
  end

  # Helpers

  defp get_export_body(conn) do
    # Use the real export endpoint so the test verifies that the drift check
    # is compatible with the actual export format served by prod
    secret = Sanbase.Utils.Config.module_get(Sanbase.Metric.Registry.Sync, :export_secret)

    conn
    |> get("/metric_registry_export?secret=#{secret}")
    |> response(200)
  end

  defp mock_remote_export(body, fun) do
    Sanbase.Mock.prepare_mock2(&Req.get/2, {:ok, %Req.Response{status: 200, body: body}})
    |> Sanbase.Mock.run_with_mocks(fun)
  end
end
