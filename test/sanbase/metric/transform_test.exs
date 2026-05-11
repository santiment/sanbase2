defmodule Sanbase.Metric.TransformTest do
  use ExUnit.Case, async: true

  alias Sanbase.Metric.Transform

  describe "transform_to_value_pairs/2" do
    test "deduces key name when only one non-datetime key exists" do
      data = [
        %{datetime: ~U[2024-01-01 00:00:00Z], price: 100.0},
        %{datetime: ~U[2024-01-02 00:00:00Z], price: 200.0}
      ]

      assert Transform.transform_to_value_pairs({:ok, data}) ==
               {:ok,
                [
                  %{value: 100.0, datetime: ~U[2024-01-01 00:00:00Z]},
                  %{value: 200.0, datetime: ~U[2024-01-02 00:00:00Z]}
                ]}
    end

    test "uses explicit key name when provided" do
      data = [
        %{datetime: ~U[2024-01-01 00:00:00Z], volume: 500, price: 100},
        %{datetime: ~U[2024-01-02 00:00:00Z], volume: 600, price: 200}
      ]

      assert Transform.transform_to_value_pairs({:ok, data}, :volume) ==
               {:ok,
                [
                  %{value: 500, datetime: ~U[2024-01-01 00:00:00Z]},
                  %{value: 600, datetime: ~U[2024-01-02 00:00:00Z]}
                ]}
    end

    test "returns empty list for empty ok result" do
      assert Transform.transform_to_value_pairs({:ok, []}) == {:ok, []}
      assert Transform.transform_to_value_pairs({:ok, []}, :price) == {:ok, []}
    end

    test "passes through errors" do
      assert Transform.transform_to_value_pairs({:error, "fail"}) == {:error, "fail"}
      assert Transform.transform_to_value_pairs({:error, "fail"}, :key) == {:error, "fail"}
    end
  end

  describe "maybe_nullify_values/1" do
    test "nullifies non-datetime non-slug fields when has_changed is 0" do
      data = [
        %{has_changed: 0, datetime: ~U[2024-01-01 00:00:00Z], slug: "bitcoin", price: 100.0},
        %{has_changed: 1, datetime: ~U[2024-01-02 00:00:00Z], slug: "bitcoin", price: 200.0}
      ]

      assert Transform.maybe_nullify_values({:ok, data}) ==
               {:ok,
                [
                  %{datetime: ~U[2024-01-01 00:00:00Z], slug: "bitcoin", price: nil},
                  %{datetime: ~U[2024-01-02 00:00:00Z], slug: "bitcoin", price: 200.0}
                ]}
    end

    test "removes has_changed key from all elements" do
      data = [
        %{has_changed: 1, datetime: ~U[2024-01-01 00:00:00Z], value: 10}
      ]

      {:ok, [result]} = Transform.maybe_nullify_values({:ok, data})
      refute Map.has_key?(result, :has_changed)
    end

    test "passes through errors" do
      assert Transform.maybe_nullify_values({:error, "err"}) == {:error, "err"}
    end
  end

  describe "remove_missing_values/1" do
    test "removes elements with has_changed == 0" do
      data = [
        %{has_changed: 1, datetime: ~U[2024-01-01 00:00:00Z], value: 10},
        %{has_changed: 0, datetime: ~U[2024-01-02 00:00:00Z], value: 0},
        %{has_changed: 1, datetime: ~U[2024-01-03 00:00:00Z], value: 20}
      ]

      assert Transform.remove_missing_values({:ok, data}) ==
               {:ok,
                [
                  %{has_changed: 1, datetime: ~U[2024-01-01 00:00:00Z], value: 10},
                  %{has_changed: 1, datetime: ~U[2024-01-03 00:00:00Z], value: 20}
                ]}
    end

    test "returns empty list when all values are missing" do
      data = [
        %{has_changed: 0, datetime: ~U[2024-01-01 00:00:00Z], value: 0}
      ]

      assert Transform.remove_missing_values({:ok, data}) == {:ok, []}
    end

    test "passes through errors" do
      assert Transform.remove_missing_values({:error, "err"}) == {:error, "err"}
    end
  end
end
