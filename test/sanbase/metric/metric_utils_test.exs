defmodule Sanbase.Metric.UtilsTest do
  use ExUnit.Case, async: true

  alias Sanbase.Metric.Utils

  doctest Sanbase.Metric.Utils

  describe "unsupported_selector_error/2" do
    test "without required fields hint" do
      result = Utils.unsupported_selector_error(%{text: "hello"})
      assert result =~ "is not supported"
      assert result =~ ":text"
      refute result =~ "must have"
    end

    test "with required fields hint" do
      result = Utils.unsupported_selector_error(%{text: "hello"}, "slug")
      assert result =~ "is not supported"
      assert result =~ "must have the following fields: slug"
      assert result =~ ":text"
    end

    test "with multiple keys in selector" do
      result = Utils.unsupported_selector_error(%{a: 1, b: 2})
      assert result =~ ":a"
      assert result =~ ":b"
    end
  end
end
