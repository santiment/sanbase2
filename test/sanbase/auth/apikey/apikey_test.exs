defmodule Sanbase.Accounts.ApiKeyTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Accounts.{
    User,
    Apikey
  }

  setup do
    {:ok, user} = User.find_or_insert_by(:email, "as819asdnmaso1011@santiment.net")

    %{user: user}
  end

  test "masking apikey" do
    apikey = String.duplicate("x", 16) <> "_" <> String.duplicate("y", 16)
    masked_apikey = Apikey.mask_apikey(apikey)
    assert masked_apikey == "xxxxxx*************************yy"
  end

  test "get user by apikey", %{user: user} do
    {:ok, apikey} = Apikey.generate_apikey(user)
    {:ok, retrieved_user} = Apikey.apikey_to_user(apikey)
    assert user.id == retrieved_user.id
  end

  # Will find th token in the db but will fail at the hmac part
  test "fail when apikey second part is invalid", %{user: user} do
    {:ok, apikey} = Apikey.generate_apikey(user)
    apikey = apikey <> "s"
    {:error, error} = Apikey.apikey_to_user(apikey)
    assert error =~ "Apikey '#{Apikey.mask_apikey(apikey)}' is not valid"
  end

  # Won't find the token in the db
  test "fail when the apikey first part is invalid", %{user: user} do
    {:ok, apikey} = Apikey.generate_apikey(user)
    apikey = "s" <> apikey
    {:error, error} = Apikey.apikey_to_user(apikey)
    assert error =~ "Apikey '#{Apikey.mask_apikey(apikey)}' is not valid"
  end

  # Splitting the apikey will fail
  test "fail when the apikey cannot be split properly" do
    apikey = "notproperlyformatedapikey"
    {:error, error} = Apikey.apikey_to_user("notproperlyformatedapikey")

    assert error =~
             "Apikey '#{apikey}' is malformed - it must have two string parts separated by underscore"
  end

  test "revoke apikey", %{user: user} do
    # Create and test the apikey
    {:ok, apikey} = Apikey.generate_apikey(user)
    {:ok, retrieved_user} = Apikey.apikey_to_user(apikey)
    assert user.id == retrieved_user.id

    # Revoke the apikey and expect it to be non valid
    :ok = Apikey.revoke_apikey(user, apikey)

    assert {:error, "Apikey '#{Apikey.mask_apikey(apikey)}' is not valid"} ==
             Apikey.apikey_to_user(apikey)
  end

  test "get list of apikeys", %{user: user} do
    {:ok, apikey1} = Apikey.generate_apikey(user)
    {:ok, apikey2} = Apikey.generate_apikey(user)

    assert {:ok, [apikey1, apikey2]} == Apikey.apikeys_list(user)
  end

  test "get list of apikeys when there are none", %{user: user} do
    assert {:ok, []} == Apikey.apikeys_list(user)
  end
end
