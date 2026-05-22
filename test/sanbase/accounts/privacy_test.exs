defmodule Sanbase.Accounts.PrivacyTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Accounts

  setup do
    protected = insert(:user)
    unprotected = insert(:user)
    Sanbase.PrivacyCacheSeed.seed!([protected.id])
    {:ok, protected: protected, unprotected: unprotected}
  end

  describe "activity_traces_hidden?/1" do
    test "returns true for ids in the seeded protected set", %{protected: user} do
      assert Accounts.activity_traces_hidden?(user.id)
    end

    test "returns false for ids outside the set", %{unprotected: user} do
      refute Accounts.activity_traces_hidden?(user.id)
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
