defmodule Sanbase.Accounts.PrivacyTest do
  use ExUnit.Case, async: true

  alias Sanbase.Accounts

  describe "privacy_protected?/1" do
    test "returns true for ids in the protected set" do
      [id | _] = Accounts.privacy_protected_user_ids() |> Enum.to_list()
      assert Accounts.privacy_protected?(id)
    end

    test "returns false for ids outside the set" do
      protected = Accounts.privacy_protected_user_ids()
      outside = Enum.find(1..10_000, fn id -> not MapSet.member?(protected, id) end)
      refute Accounts.privacy_protected?(outside)
    end

    test "returns false for nil and non-integer inputs" do
      refute Accounts.privacy_protected?(nil)
      refute Accounts.privacy_protected?("1")
      refute Accounts.privacy_protected?(:foo)
    end
  end

  describe "masked_sentinel/0" do
    test "is a stable string" do
      assert Accounts.masked_sentinel() == "<masked>"
    end
  end
end
