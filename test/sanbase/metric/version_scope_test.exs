defmodule Sanbase.Metric.VersionScopeTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Metric.Registry

  test "the github metrics are in the github scope" do
    for metric <- [
          "dev_activity",
          "github_activity",
          "dev_activity_contributors_count",
          "github_activity_contributors_count"
        ] do
      assert Sanbase.Metric.version_scope(metric) == "github"
    end
  end

  test "the social data and twitter metrics are in the social scope" do
    for metric <- ["community_messages_count_total", "nft_social_volume", "twitter_followers"] do
      assert Sanbase.Metric.version_scope(metric) == "social", metric
    end
  end

  test "the other metrics and the unknown ones are in the global scope" do
    assert Sanbase.Metric.version_scope("price_usd_5m") == "global"
    assert Sanbase.Metric.version_scope("not_a_metric") == "global"
  end

  test "the scope of a clickhouse metric comes from the registry" do
    Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.MetricAdapter.Registry.version_scope_map/0,
      %{"price_usd_5m" => "github", "social_volume_total" => "social"}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert Sanbase.Metric.version_scope("price_usd_5m") == "github"
      assert Sanbase.Metric.version_scope("social_volume_total") == "social"
      assert Sanbase.Metric.version_scope("daily_active_addresses") == "global"
    end)
  end

  test "populating from the JSON files keeps the version scope set in the DB" do
    json_map = %{"name" => "some_metric_1d", "metric" => "some_metric", "table" => "t"}

    refute Map.has_key?(Registry.Populate.json_map_to_registry_params(json_map), :version_scope)

    assert %{version_scope: "social"} =
             Registry.Populate.json_map_to_registry_params(
               Map.put(json_map, "version_scope", "social")
             )

    changeset =
      Registry.changeset(
        %Registry{version_scope: "social"},
        Registry.Populate.json_map_to_registry_params(json_map)
      )

    assert Ecto.Changeset.get_field(changeset, :version_scope) == "social"

    changeset = Registry.Populate.json_map_to_registry_changeset(json_map)
    assert Ecto.Changeset.get_field(changeset, :version_scope) == "global"
  end

  test "the registry accepts only the known scopes" do
    assert %{version_scope: ["is invalid"]} =
             errors_on(Registry.changeset(%Registry{}, %{version_scope: "nope"}))

    for scope <- ["global", "github", "social"] do
      refute Map.has_key?(
               errors_on(Registry.changeset(%Registry{}, %{version_scope: scope})),
               :version_scope
             )
    end

    assert %Registry{}.version_scope == "global"
  end
end
