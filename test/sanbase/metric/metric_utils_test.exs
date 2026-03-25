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

    test "with a full hint sentence" do
      result =
        Utils.unsupported_selector_error(
          %{text: "hello"},
          "The selector must have the following field: slug"
        )

      assert result =~ "is not supported"
      assert result =~ "The selector must have the following field: slug."
      assert result =~ "Provided selector fields: :text"
    end

    test "with multiple keys in selector" do
      result = Utils.unsupported_selector_error(%{a: 1, b: 2})
      assert result =~ ":a"
      assert result =~ ":b"
    end

    test "formats 'at least one of' hint naturally" do
      result =
        Utils.unsupported_selector_error(
          %{foo: 1},
          "The selector must have at least one of the following fields: slug, organization, organizations"
        )

      assert result =~
               "The selector must have at least one of the following fields: slug, organization, organizations."

      refute result =~ "the following fields: at least one"
    end

    test "matches original clickhouse adapter error format" do
      result =
        Utils.unsupported_selector_error(
          %{foo: 1},
          "The selector must have at least one of the following fields: slug, address, contractAddress"
        )

      expected =
        "The provided selector %{foo: 1} is not supported. " <>
          "The selector must have at least one of the following fields: slug, address, contractAddress. " <>
          "Provided selector fields: :foo"

      assert result == expected
    end

    test "matches original twitter adapter error format" do
      result =
        Utils.unsupported_selector_error(
          %{foo: 1},
          "The selector must have the following field: slug"
        )

      expected =
        "The provided selector %{foo: 1} is not supported. " <>
          "The selector must have the following field: slug. " <>
          "Provided selector fields: :foo"

      assert result == expected
    end
  end
end
