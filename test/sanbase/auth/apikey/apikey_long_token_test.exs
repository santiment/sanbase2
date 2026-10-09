defmodule Sanbase.Accounts.ApikeyLongTokenTest do
  # Reproduces Sentry SANBASE-BACKEND-PROD-GA9:
  #   ArgumentError in :erlang.binary_part/3 ("3rd argument: out of range")
  #   Hmac.hmac/1 <- Hmac.generate_apikey/1 <- Hmac.apikey_valid?/2
  #   <- Apikey.apikey_to_user/1 <- Sanbase.MCP.AuthPlug.try_apikey/1
  #
  # The HMAC-SHA256 digest is 32 bytes, i.e. 56 base32 chars. `hmac/1` slices
  # `byte_size(token)` chars from it, so any "<token>_<rest>" credential whose
  # token part is longer than 56 bytes raises instead of being rejected.
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Accounts.{Apikey, Hmac}

  # 57 chars - one more than the base32-encoded HMAC digest (56 chars)
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
