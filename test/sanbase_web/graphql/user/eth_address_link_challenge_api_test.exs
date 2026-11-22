defmodule SanbaseWeb.Graphql.EthAddressLinkChallengeApiTest do
  @moduledoc """
  SECURITY_ANALYSIS.md C6: linking a wallet (`addUserEthAddress`) must use a
  one-time challenge bound to the operation and the account, like the wallet
  login. A fixed-message signature never expires, so whoever obtained one could
  attach the victim's wallet (SAN balance / NFT privileges) to their account.
  """
  # Mock replaces modules globally, so these tests cannot be async.
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import ExUnit.CaptureLog

  alias Sanbase.Accounts.{EthAccount, EthLoginChallenge, Turnstile}
  alias Sanbase.Billing.Subscription.LiquiditySubscription
  alias Sanbase.FeatureToggle
  alias Sanbase.InternalServices.Ethauth

  # Unused Ropsten testnet address. The signature check is mocked.
  @address "0x9024d48cc7be15343dfd76ef051fa5264cfbf7a9"
  @signature "0xeba4d1a091ca6e7cb0_signature_check_will_be_mocked"

  setup do
    user = insert(:user)
    other = insert(:user)

    %{
      user: user,
      other: other,
      conn: setup_jwt_auth(build_conn(), user),
      other_conn: setup_jwt_auth(build_conn(), other)
    }
  end

  # Every signature is "valid": these tests are about which messages/nonces
  # the server accepts, not about the cryptography.
  defp with_signature_mocks(fun) do
    test_pid = self()

    Sanbase.Mock.prepare_mock(Ethauth, :valid_signature?, fn address, signature ->
      send(test_pid, {:legacy_verified, address, signature})
      true
    end)
    |> Sanbase.Mock.prepare_mock(Ethauth, :valid_signature?, fn address, signature, message ->
      send(test_pid, {:verified, address, signature, message})
      true
    end)
    |> Sanbase.Mock.prepare_mock2(&Turnstile.validate/2, :ok)
    |> Sanbase.Mock.prepare_mock2(&LiquiditySubscription.user_staked_in_uniswap_v2/1, false)
    |> Sanbase.Mock.prepare_mock2(&LiquiditySubscription.user_staked_in_uniswap_v3/1, false)
    |> Sanbase.Mock.run_with_mocks(fun)
  end

  test "the link challenge names the operation and the account", context do
    %{"message" => message, "nonce" => nonce} = link_challenge(context.conn)

    assert message =~ "Link address #{@address} to Santiment account #{context.user.id}"
    assert message =~ "Nonce: #{nonce}"
  end

  test "the link challenge requires a logged-in user" do
    assert link_challenge_response(build_conn()) |> first_error() =~ "unauthorized"
  end

  test "a signed link challenge adds the address, checked against the stored message",
       context do
    %{"message" => message, "nonce" => nonce} = link_challenge(context.conn)

    with_signature_mocks(fn ->
      assert %{"data" => %{"addUserEthAddress" => %{"ethAccounts" => [%{"address" => @address}]}}} =
               add_address(context.conn, %{nonce: nonce})
    end)

    assert_received {:verified, @address, @signature, ^message}
    assert %EthAccount{user_id: user_id} = EthAccount.by_address(@address)
    assert user_id == context.user.id
  end

  test "an address with surrounding whitespace is trimmed in both mutations", context do
    padded = "  #{@address} "
    %{"message" => message, "nonce" => nonce} = link_challenge(context.conn, padded)

    with_signature_mocks(fn ->
      assert %{"data" => %{"addUserEthAddress" => %{"ethAccounts" => [%{"address" => @address}]}}} =
               add_address(context.conn, %{nonce: nonce}, padded)
    end)

    assert_received {:verified, @address, @signature, ^message}
  end

  test "a link challenge can be used once", context do
    %{"nonce" => nonce} = link_challenge(context.conn)

    with_signature_mocks(fn ->
      add_address(context.conn, %{nonce: nonce})
      Sanbase.Repo.delete_all(EthAccount)

      assert add_address(context.conn, %{nonce: nonce}) |> first_error() =~
               "Invalid or expired challenge"
    end)
  end

  test "another account cannot use the challenge (or signature) issued for this one",
       context do
    %{"nonce" => nonce} = link_challenge(context.conn)

    with_signature_mocks(fn ->
      assert add_address(context.other_conn, %{nonce: nonce}) |> first_error() =~
               "Invalid or expired challenge"
    end)

    assert EthAccount.by_address(@address) == nil
  end

  test "a login challenge cannot be used to link a wallet", context do
    {:ok, %{nonce: login_nonce}} = EthLoginChallenge.create(@address)

    with_signature_mocks(fn ->
      assert add_address(context.conn, %{nonce: login_nonce}) |> first_error() =~
               "Invalid or expired challenge"
    end)

    assert EthAccount.by_address(@address) == nil
  end

  test "a link challenge cannot be used to log in", context do
    %{"nonce" => link_nonce} = link_challenge(context.conn)

    with_signature_mocks(fn ->
      capture_log(fn ->
        assert eth_login(build_conn(), link_nonce) |> first_error() ==
                 "Wallet Login verification failed"
      end)
    end)

    assert EthAccount.by_address(@address) == nil
  end

  describe "legacy fixed-message linking" do
    test "works while eth_login_legacy is enabled", context do
      with_signature_mocks(fn ->
        assert %{"data" => %{"addUserEthAddress" => %{"ethAccounts" => [_]}}} =
                 add_address(context.conn, %{message_hash: "0xhash"})
      end)

      assert_received {:legacy_verified, @address, @signature}
    end

    test "is refused when eth_login_legacy is disabled", context do
      {:ok, _} = FeatureToggle.disable_eth_login_legacy()

      with_signature_mocks(fn ->
        assert add_address(context.conn, %{message_hash: "0xhash"}) |> first_error() =~
                 "Sign a challenge from ethAddressLinkChallenge"
      end)

      refute_received {:legacy_verified, _, _}
      assert EthAccount.by_address(@address) == nil
    end
  end

  defp first_error(response), do: get_in(response, ["errors", Access.at(0), "message"])

  defp link_challenge(conn, address \\ @address) do
    link_challenge_response(conn, address) |> get_in(["data", "ethAddressLinkChallenge"])
  end

  defp link_challenge_response(conn, address \\ @address) do
    mutation = """
    mutation {
      ethAddressLinkChallenge(address: "#{address}") { message nonce expiresAt }
    }
    """

    conn |> post("/graphql", mutation_skeleton(mutation)) |> json_response(200)
  end

  defp add_address(conn, extra, address \\ @address) do
    extra_args = extra |> map_to_args()

    mutation = """
    mutation {
      addUserEthAddress(address: "#{address}", signature: "#{@signature}" #{extra_args}) {
        ethAccounts { address }
      }
    }
    """

    conn |> post("/graphql", mutation_skeleton(mutation)) |> json_response(200)
  end

  defp eth_login(conn, nonce) do
    mutation = """
    mutation {
      ethLogin(signature: "#{@signature}", address: "#{@address}", nonce: "#{nonce}", token: "t") {
        accessToken
      }
    }
    """

    conn |> post("/graphql", mutation_skeleton(mutation)) |> json_response(200)
  end
end
