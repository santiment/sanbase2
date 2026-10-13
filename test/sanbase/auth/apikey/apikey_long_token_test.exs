defmodule Sanbase.Accounts.ApikeyLongTokenTest do
  use ExUnit.Case, async: true

  test "apikey_to_user/1 returns an error for a token longer than the HMAC digest" do
    apikey = String.duplicate("a", 57) <> "_" <> String.duplicate("b", 16)

    assert {:error, error} = Sanbase.Accounts.Apikey.apikey_to_user(apikey)
    assert error =~ "is not valid"
  end
end
