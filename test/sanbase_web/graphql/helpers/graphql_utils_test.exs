defmodule SanbaseWeb.Graphql.Helpers.GraphqlUtilsTest do
  use ExUnit.Case, async: true

  alias SanbaseWeb.Graphql.Helpers.Utils

  describe "resolution_to_user_id_or_nil/1" do
    test "extracts user_id from nested resolution context" do
      resolution = %{context: %{auth: %{current_user: %{id: 42}}}}
      assert Utils.resolution_to_user_id_or_nil(resolution) == 42
    end

    test "returns nil when no auth context" do
      assert Utils.resolution_to_user_id_or_nil(%{context: %{}}) == nil
    end

    test "returns nil for completely different structure" do
      assert Utils.resolution_to_user_id_or_nil(%{}) == nil
    end
  end

  describe "selector_args_to_opts/1" do
    test "returns aggregation from args" do
      args = %{aggregation: :avg}
      assert {:ok, opts} = Utils.selector_args_to_opts(args)
      assert Keyword.get(opts, :aggregation) == :avg
    end

    test "returns nil aggregation when not provided" do
      args = %{}
      assert {:ok, opts} = Utils.selector_args_to_opts(args)
      assert Keyword.get(opts, :aggregation) == nil
    end

    test "extracts source from selector" do
      args = %{aggregation: nil, selector: %{source: "twitter"}}
      assert {:ok, opts} = Utils.selector_args_to_opts(args)
      assert Keyword.get(opts, :source) == "twitter"
    end

    test "does not add selector fields when selector is nil" do
      args = %{aggregation: nil, selector: nil}
      assert {:ok, opts} = Utils.selector_args_to_opts(args)
      assert Keyword.get(opts, :source) == nil
      assert Keyword.get(opts, :additional_filters) == nil
    end
  end

  describe "fit_from_datetime/2" do
    test "drops data points before the from datetime" do
      data = [
        %{datetime: ~U[2024-01-01 00:00:00Z], value: 1},
        %{datetime: ~U[2024-01-02 00:00:00Z], value: 2},
        %{datetime: ~U[2024-01-03 00:00:00Z], value: 3}
      ]

      args = %{from: ~U[2024-01-02 00:00:00Z], interval: "1d"}

      assert {:ok, result} = Utils.fit_from_datetime(data, args)
      assert length(result) == 2
      assert hd(result).value == 2
    end

    test "keeps all data when all points are after from" do
      data = [
        %{datetime: ~U[2024-01-05 00:00:00Z], value: 1},
        %{datetime: ~U[2024-01-06 00:00:00Z], value: 2}
      ]

      args = %{from: ~U[2024-01-01 00:00:00Z], interval: "1d"}

      assert {:ok, result} = Utils.fit_from_datetime(data, args)
      assert length(result) == 2
    end

    test "returns ok with non-datetime-list data unchanged" do
      assert {:ok, []} = Utils.fit_from_datetime([], %{from: ~U[2024-01-01 00:00:00Z]})
    end
  end

  describe "sanitize_trigger_settings/1" do
    test "removes private keys from a map" do
      settings = %{
        type: "metric_signal",
        target: %{slug: "bitcoin"},
        channel: "telegram",
        template: "some template",
        filtered_target: ["bitcoin"]
      }

      result = Utils.sanitize_trigger_settings(settings)
      refute Map.has_key?(result, :channel)
      refute Map.has_key?(result, :template)
      assert Map.has_key?(result, :type)
      assert Map.has_key?(result, :target)
    end

    test "removes private string keys from a map" do
      settings = %{
        "type" => "metric_signal",
        "channel" => "telegram",
        "template" => "some template"
      }

      result = Utils.sanitize_trigger_settings(settings)
      refute Map.has_key?(result, "channel")
      refute Map.has_key?(result, "template")
      assert Map.has_key?(result, "type")
    end
  end
end
