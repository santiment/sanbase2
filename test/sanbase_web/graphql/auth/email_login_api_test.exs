defmodule SanbaseWeb.Graphql.EmailLoginApiTest do
  use SanbaseWeb.ConnCase

  import SanbaseWeb.Graphql.TestHelpers

  test "eth login", context do
    # This address is an unused address on the Ropsten testnet. It is not a mainnet
    # address holding any coins. The signature is not a real signature as the
    # call to verify_signature/3 will be mocked
    address = "0x9024d48cc7be15343dfd76ef051fa5264cfbf7a9"
    messageHash = "0xff8ca2965b505cabd1156342c1dfa72c11e7c5e00ff839a12af71e8a7d231731"
    signature = "0xeba4d1a091ca6e7cb0_signature_check_will_be_mocked"

    mutation = """
    mutation {
      ethLogin(
        signature: "#{signature}"
        address: "#{address}"
        messageHash: "#{messageHash}"){
          user{ id firstLogin }
          accessToken
          refreshToken
        }
    }
    """

    # Mock the external call to Ethauth. Mock the call to trial subscription creation.
    Sanbase.Mock.prepare_mock2(&Sanbase.InternalServices.Ethauth.verify_signature/3, true)
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.Billing.maybe_create_liquidity_or_trial_subscription/1,
      :ok
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        context.conn
        |> post("/graphql", mutation_skeleton(mutation))
        |> json_response(200)
        |> get_in(["data", "ethLogin"])

      assert is_binary(result["user"]["id"])
      assert is_integer(String.to_integer(result["user"]["id"]))
      assert result["user"]["firstLogin"]
      assert is_binary(result["accessToken"])
      assert is_binary(result["refreshToken"])
    end)
  end

  test "email login", context do
  end

  test "google oauth first login", context do
  end

  test "google oauth login for already existing email", context do
  end

  test "twitter oauth first login", context do
  end

  test "twitter oauth login for already existing email", context do
  end
end
