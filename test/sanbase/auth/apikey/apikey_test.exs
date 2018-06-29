defmodule Sanbase.Auth.ApiKeyTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Auth.{
    User,
    Apikey
  }

  setup do
    {:ok, user} = User.find_or_insert_by_email("test@santiment.net")

    %{
      user: user
    }
  end

  test "create apikey and retrieve user", %{user: user} do
    {:ok, apikey} = Apikey.generate_apikey(user)

    {:ok, retrieved_user} = Apikey.apikey_to_user(apikey)

    assert user == retrieved_user
  end
end
