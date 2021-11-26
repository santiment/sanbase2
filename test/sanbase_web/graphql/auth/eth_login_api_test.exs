defmodule SanbaseWeb.Graphql.EthLoginApiTest do
  use SanbaseWeb.ConnCase

  import Mock
  import ExUnit.CaptureLog
  import SanbaseWeb.Graphql.TestHelpers

  test "first eth login success - create user and eth account", context do
    # This address is an unused address on the Ropsten testnet. It is not a mainnet
    # address holding any coins. The signature is not a real signature as the
    # call to verify_signature/3 will be mocked
    address = "0x9024d48cc7be15343dfd76ef051fa5264cfbf7a9"
    message_hash = "0xff8ca2965b505cabd1156342c1dfa72c11e7c5e00ff839a12af71e8a7d231731"
    signature = "0xeba4d1a091ca6e7cb0_signature_check_will_be_mocked"

    # Mock the external call to Ethauth. Mock the call to trial subscription creation.
    Sanbase.Mock.prepare_mock2(&Sanbase.InternalServices.Ethauth.verify_signature/3, true)
    |> Sanbase.Mock.prepare_mock2(&Sanbase.Accounts.EthAccount.san_staked_address/2, 0.0)
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        eth_login(context.conn, address, signature, message_hash)
        |> get_in(["data", "ethLogin"])

      assert result["user"]["firstLogin"] == true

      assert is_binary(result["user"]["id"])
      assert is_integer(String.to_integer(result["user"]["id"]))
      assert is_binary(result["accessToken"])
      assert is_binary(result["refreshToken"])

      assert called(Sanbase.Accounts.EthAccount.san_staked_address(:_, :_))
    end)
  end

  test "eth login success - existing user", context do
    # This address is an unused address on the Ropsten testnet. It is not a mainnet
    # address holding any coins. The signature is not a real signature as the
    # call to verify_signature/3 will be mocked
    address = "0x9024d48cc7be15343dfd76ef051fa5264cfbf7a9"
    message_hash = "0xff8ca2965b505cabd1156342c1dfa72c11e7c5e00ff839a12af71e8a7d231731"
    signature = "0xeba4d1a091ca6e7cb0_signature_check_will_be_mocked"

    # Mock the external call to Ethauth. Mock the call to trial subscription creation.
    Sanbase.Mock.prepare_mock2(&Sanbase.InternalServices.Ethauth.verify_signature/3, true)
    |> Sanbase.Mock.prepare_mock2(&Sanbase.Accounts.EthAccount.san_staked_address/2, 0.0)
    |> Sanbase.Mock.run_with_mocks(fn ->
      _ = eth_login(context.conn, address, signature, message_hash)

      result =
        eth_login(context.conn, address, signature, message_hash)
        |> get_in(["data", "ethLogin"])

      assert result["user"]["firstLogin"] == false

      assert is_binary(result["user"]["id"])
      assert is_integer(String.to_integer(result["user"]["id"]))
      assert is_binary(result["accessToken"])
      assert is_binary(result["refreshToken"])

      assert called(Sanbase.Accounts.EthAccount.san_staked_address(:_, :_))
    end)
  end

  test "eth login works after changing username", context do
    # This address is an unused address on the Ropsten testnet. It is not a mainnet
    # address holding any coins. The signature is not a real signature as the
    # call to verify_signature/3 will be mocked
    address = "0x9024d48cc7be15343dfd76ef051fa5264cfbf7a9"
    message_hash = "0xff8ca2965b505cabd1156342c1dfa72c11e7c5e00ff839a12af71e8a7d231731"
    signature = "0xeba4d1a091ca6e7cb0_signature_check_will_be_mocked"

    # Mock the external call to Ethauth. Mock the call to trial subscription creation.
    Sanbase.Mock.prepare_mock2(&Sanbase.InternalServices.Ethauth.verify_signature/3, true)
    |> Sanbase.Mock.prepare_mock2(&Sanbase.Accounts.EthAccount.san_staked_address/2, 0.0)
    |> Sanbase.Mock.run_with_mocks(fn ->
      user_id =
        eth_login(context.conn, address, signature, message_hash)
        |> get_in(["data", "ethLogin", "user", "id"])
        |> String.to_integer()

      {:ok, _} =
        Sanbase.Accounts.get_user!(user_id)
        |> Sanbase.Accounts.User.change_username("some_new_username")

      user_id2 =
        eth_login(context.conn, address, signature, message_hash)
        |> get_in(["data", "ethLogin", "user", "id"])
        |> String.to_integer()

      assert user_id == user_id2
    end)
  end

  test "eth login fail", context do
    address = "0x9024d48cc7be15343dfd76ef051fa5264cfbf7a9"
    message_hash = "0xff8ca2965b_invalid_hash"
    signature = "0xeba4d1a091ca6e7cb0_signature_check_will_be_mocked"

    # Mock the external call to Ethauth
    Sanbase.Mock.prepare_mock2(&Sanbase.InternalServices.Ethauth.verify_signature/3, true)
    |> Sanbase.Mock.run_with_mocks(fn ->
      log =
        capture_log(fn ->
          error_msg =
            eth_login(context.conn, address, signature, message_hash)
            |> get_in(["errors", Access.at(0), "message"])

          assert error_msg == "Login failed"
        end)

      assert log =~ "Login failed: invalid signature"
    end)
  end

  defp eth_login(conn, address, signature, message_hash) do
    mutation = """
    mutation {
      ethLogin(
        signature: "#{signature}"
        address: "#{address}"
        messageHash: "#{message_hash}"){
          user{ id firstLogin }
          accessToken
          refreshToken
        }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end
end
