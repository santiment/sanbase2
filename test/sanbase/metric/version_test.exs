defmodule Sanbase.Metric.VersionTest do
  use ExUnit.Case, async: true

  alias Sanbase.Metric.Version

  test "version 1.x is base" do
    assert Version.classify("1.0") == :base
    assert Version.classify("1.1") == :base
  end

  test "N.0 is standard" do
    for version <- ["2.0", "3.0", "4.0", "2.0.1"] do
      assert Version.classify(version) == :standard, version
    end
  end

  test "N.M with non-zero M is point-in-time, including point releases" do
    for version <- ["2.1", "2.1.1", "2.1.2", "3.1", "4.1", "2.2"] do
      assert Version.classify(version) == :pit, version
    end
  end

  test "anything that is not a dotted number is other" do
    for version <- ["Experimental (Weighted Age)", "modern:v1", "2", "2.x", "2.1a", "", nil] do
      assert Version.classify(version) == :other, inspect(version)
    end
  end
end
