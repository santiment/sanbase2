defmodule Sanbase.Accounts.ApikeyLongTokenTest do
  # Tokens longer than the HMAC digest crashed binary_part/3
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Accounts.{Apikey, Hmac}

  @long_token String.duplicate("a", 57)
  @long_apikey @long_token <> "_" <> String.duplicate("b", 16)

  test "Hmac.apikey_valid?/2 returns false for a token longer than the HMAC digest" do
    assert Hmac.apikey_valid?(@long_token, @long_apikey) == false
  end

  test "Apikey.apikey_to_user/1 returns an error for a token longer than the HMAC digest" do
    assert {:error, error} = Apikey.apikey_to_user(@long_apikey)
    assert error =~ "is not valid"
  end

  test "MCP AuthPlug rejects such a credential with 401 instead of crashing", %{conn: conn} do
    conn =
      conn
      |> Plug.Conn.put_req_header("authorization", "Bearer " <> @long_apikey)
      |> Map.put(:method, "POST")
      |> Map.put(:body_params, %{"method" => "tools/call"})
      |> Sanbase.MCP.AuthPlug.call([])

    assert conn.halted
    assert conn.status == 401
  end
end
