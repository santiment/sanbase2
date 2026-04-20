defmodule SanbaseWeb.MetricRegistryControllerTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Utils.Config

  setup do
    secret = Config.module_get(Sanbase.Metric.Registry.Sync, :export_secret)
    %{secret: secret}
  end

  describe "GET /metric_registry_export" do
    test "returns JSONL of all registry entries when secret is valid", %{
      conn: conn,
      secret: secret
    } do
      body =
        conn
        |> get("/metric_registry_export", %{"secret" => secret})
        |> response(200)

      entries =
        body
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)

      assert length(entries) > 1
      assert Enum.all?(entries, &is_map/1)
      assert Enum.all?(entries, &Map.has_key?(&1, "metric"))
      assert Enum.all?(entries, &Map.has_key?(&1, "internal_metric"))
    end

    test "returns 403 without secret", %{conn: conn} do
      conn
      |> get("/metric_registry_export")
      |> response(403)
    end

    test "returns 403 with wrong secret", %{conn: conn} do
      conn
      |> get("/metric_registry_export", %{"secret" => "not_the_secret"})
      |> response(403)
    end

    test "does not accept sync_secret", %{conn: conn} do
      sync_secret = Config.module_get(Sanbase.Metric.Registry.Sync, :sync_secret)
      export_secret = Config.module_get(Sanbase.Metric.Registry.Sync, :export_secret)
      assert sync_secret != export_secret

      conn
      |> get("/metric_registry_export", %{"secret" => sync_secret})
      |> response(403)
    end
  end
end
