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

  test "create apikey and retrieve user", %{user: user} do
    {:ok, apikey} = Apikey.generate_apikey(user)
    {:ok, retrieved_user} = Apikey.apikey_to_user(apikey)
    assert user == retrieved_user
  end

  test "revoke apikey", %{user: user} do
    # Create and test the apikey
    {:ok, apikey} = Apikey.generate_apikey(user)
    {:ok, retrieved_user} = Apikey.apikey_to_user(apikey)
    assert user == retrieved_user

    # Revoke the apikey and expect it to be non valid
    :ok = Apikey.revoke_apikey(apikey)
    assert {:error, "Apikey not valid"} == Apikey.apikey_to_user(apikey)
  end
end
