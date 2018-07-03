defmodule Sanbase.Auth.ApiKeyTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Auth.{
    User,
    Apikey
  }

  setup do
    {:ok, user} = User.find_or_insert_by_email("as819asdnmaso1011@santiment.net")

    %{
      user: user
    }
  end

  test "get user by apikey", %{user: user} do
    {:ok, apikey} = Apikey.generate_apikey(user)
    {:ok, retrieved_user} = Apikey.apikey_to_user(apikey)
    assert user == retrieved_user
  end

  # Will find th token in the db but will fail at the hmac part
  test "fail when apikey second part is invalid", %{user: user} do
    {:ok, apikey} = Apikey.generate_apikey(user)
    apikey = apikey <> "s"
    assert {:error, "Apikey not valid or malformed"} == Apikey.apikey_to_user(apikey)
  end

  # Won't find the token in the db
  test "fail when the apikey first part is invalid", %{user: user} do
    {:ok, apikey} = Apikey.generate_apikey(user)
    apikey = "s" <> apikey
    assert {:error, "Apikey not valid or malformed"} == Apikey.apikey_to_user(apikey)
  end

  # Splitting the apikey will fail
  test "fail when the apikey cannot be split properly" do
    assert {:error, "Apikey not valid or malformed"} ==
             Apikey.apikey_to_user("notproperlyformatedapikey")
  end

  test "revoke apikey", %{user: user} do
    # Create and test the apikey
    {:ok, apikey} = Apikey.generate_apikey(user)
    {:ok, retrieved_user} = Apikey.apikey_to_user(apikey)
    assert user == retrieved_user

    # Revoke the apikey and expect it to be non valid
    :ok = Apikey.revoke_apikey(user, apikey)
    assert {:error, "Apikey not valid or malformed"} == Apikey.apikey_to_user(apikey)
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
