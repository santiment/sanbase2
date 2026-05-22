defmodule Sanbase.Accounts.PrivacyTest do
  use ExUnit.Case, async: false

  alias Sanbase.Accounts

  describe "activity_traces_hidden?/1" do
    test "returns true for ids in the seeded protected set" do
      [id | _] = Accounts.activity_traces_hidden_user_ids() |> Enum.to_list()
      assert Accounts.activity_traces_hidden?(id)
    end

    test "returns false for ids outside the set" do
      protected = Accounts.activity_traces_hidden_user_ids()
      outside = Enum.find(1..10_000, fn id -> not MapSet.member?(protected, id) end)
      refute Accounts.activity_traces_hidden?(outside)
    end

    test "returns false for nil and non-integer inputs" do
      refute Accounts.activity_traces_hidden?(nil)
      refute Accounts.activity_traces_hidden?("1")
      refute Accounts.activity_traces_hidden?(:foo)
    end
  end

  describe "masked_sentinel/0" do
    test "is a stable string" do
      assert Accounts.masked_sentinel() == "<masked>"
    end
  end
end
