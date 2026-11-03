defmodule SanbaseWeb.Graphql.EthLoginChallengeApiTest do
  # Mock replaces modules globally, so these tests cannot be async.
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import ExUnit.CaptureLog

  alias Sanbase.Accounts.EthLoginChallenge
  alias Sanbase.Billing.Subscription.LiquiditySubscription
  alias Sanbase.FeatureToggle
  alias Sanbase.InternalServices.Ethauth

  # Unused Ropsten testnet address. The signature check is mocked.
  @address "0x9024d48cc7be15343dfd76ef051fa5264cfbf7a9"
  @message_hash "0xff8ca2965b505cabd1156342c1dfa72c11e7c5e00ff839a12af71e8a7d231731"
  @signature "0xeba4d1a091ca6e7cb0_signature_check_will_be_mocked"
  @failed "Wallet Login verification failed"

  test "ethLoginChallenge returns a message to sign and a nonce", context do
    result = challenge(context.conn, @address) |> get_in(["data", "ethLoginChallenge"])

    assert result["message"] =~ "Login in Santiment with address #{@address}"
    assert result["message"] =~ "Nonce: #{result["nonce"]}"
    assert is_binary(result["expiresAt"])
  end

  test "ethLoginChallenge rejects an invalid address", context do
    error = challenge(context.conn, "nope") |> get_in(["errors", Access.at(0), "message"])

    assert error == "Invalid wallet address"
  end

  test "login with a signed challenge, checked against the stored message", context do
    %{"nonce" => nonce, "message" => message} =
      challenge(context.conn, @address) |> get_in(["data", "ethLoginChallenge"])

    test_pid = self()

    verify = fn address, signature, signed_message ->
      send(test_pid, {:verified, address, signature, signed_message})
      true
    end

    Sanbase.Mock.prepare_mock(Ethauth, :valid_signature?, verify)
    |> Sanbase.Mock.prepare_mock2(&LiquiditySubscription.user_staked_in_uniswap_v2/1, false)
    |> Sanbase.Mock.prepare_mock2(&LiquiditySubscription.user_staked_in_uniswap_v3/1, false)
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = eth_login(context.conn, %{nonce: nonce}) |> get_in(["data", "ethLogin"])

      assert is_binary(result["accessToken"])
      assert is_binary(result["user"]["id"])
    end)

    # The signature was checked against the challenge message, not the fixed text.
    assert_received {:verified, @address, @signature, ^message}
  end

  test "a challenge can be used for one login only", context do
    %{"nonce" => nonce} =
      challenge(context.conn, @address) |> get_in(["data", "ethLoginChallenge"])

    with_login_mocks(true, fn ->
      assert eth_login(context.conn, %{nonce: nonce}) |> get_in(["data", "ethLogin"])

      capture_log(fn ->
        error = eth_login(context.conn, %{nonce: nonce}) |> first_error()
        assert error == @failed
      end)
    end)
  end

  test "a wrong signature does not use up the challenge", context do
    %{"nonce" => nonce} =
      challenge(context.conn, @address) |> get_in(["data", "ethLoginChallenge"])

    with_login_mocks(false, fn ->
      capture_log(fn ->
        assert eth_login(context.conn, %{nonce: nonce}) |> first_error() == @failed
      end)
    end)

    assert {:ok, _} = EthLoginChallenge.get_open(@address, nonce)

    with_login_mocks(true, fn ->
      assert eth_login(context.conn, %{nonce: nonce})
             |> get_in(["data", "ethLogin", "accessToken"])
    end)
  end

  test "an unknown nonce is rejected", context do
    with_login_mocks(true, fn ->
      capture_log(fn ->
        assert eth_login(context.conn, %{nonce: "unknown"}) |> first_error() == @failed
      end)
    end)
  end

  test "an expired nonce is rejected", context do
    %{"nonce" => nonce} =
      challenge(context.conn, @address) |> get_in(["data", "ethLoginChallenge"])

    past = DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second)

    Sanbase.Repo.get_by!(EthLoginChallenge, nonce: nonce)
    |> Ecto.Changeset.change(expires_at: past)
    |> Sanbase.Repo.update!()

    with_login_mocks(true, fn ->
      capture_log(fn ->
        assert eth_login(context.conn, %{nonce: nonce}) |> first_error() == @failed
      end)
    end)
  end

  test "an address with surrounding spaces logs in to the same wallet", context do
    %{"nonce" => nonce} =
      challenge(context.conn, " #{@address} ") |> get_in(["data", "ethLoginChallenge"])

    with_login_mocks(true, fn ->
      result =
        eth_login(context.conn, %{nonce: nonce, address: " #{@address} "})
        |> get_in(["data", "ethLogin"])

      assert result["user"]["ethAccounts"] |> hd() |> Map.get("address") == @address
    end)
  end

  describe "legacy fixed-message login" do
    test "works while eth_login_legacy is enabled", context do
      with_login_mocks(true, fn ->
        result =
          eth_login(context.conn, %{message_hash: @message_hash})
          |> get_in(["data", "ethLogin"])

        assert is_binary(result["accessToken"])
      end)
    end

    test "is refused when eth_login_legacy is disabled, the challenge still works",
         context do
      {:ok, _} = FeatureToggle.disable_eth_login_legacy()

      with_login_mocks(true, fn ->
        log =
          capture_log(fn ->
            assert eth_login(context.conn, %{message_hash: @message_hash}) |> first_error() ==
                     @failed
          end)

        assert log =~ "legacy_eth_login_disabled"

        %{"nonce" => nonce} =
          challenge(context.conn, @address) |> get_in(["data", "ethLoginChallenge"])

        assert eth_login(context.conn, %{nonce: nonce})
               |> get_in(["data", "ethLogin", "accessToken"])
      end)
    end

    test "a wrong message hash is refused", context do
      with_login_mocks(true, fn ->
        capture_log(fn ->
          assert eth_login(context.conn, %{message_hash: "0xdeadbeef"}) |> first_error() ==
                   @failed
        end)
      end)
    end
  end

  defp with_login_mocks(signature_valid?, fun) do
    Sanbase.Mock.prepare_mock2(&Ethauth.valid_signature?/2, signature_valid?)
    |> Sanbase.Mock.prepare_mock2(&Ethauth.valid_signature?/3, signature_valid?)
    |> Sanbase.Mock.prepare_mock2(&LiquiditySubscription.user_staked_in_uniswap_v2/1, false)
    |> Sanbase.Mock.prepare_mock2(&LiquiditySubscription.user_staked_in_uniswap_v3/1, false)
    |> Sanbase.Mock.run_with_mocks(fun)
  end

  defp first_error(response), do: get_in(response, ["errors", Access.at(0), "message"])

  defp challenge(conn, address) do
    mutation = """
    mutation {
      ethLoginChallenge(address: "#{address}") {
        message
        nonce
        expiresAt
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  defp eth_login(conn, extra) do
    {address, extra} = Map.pop(extra, :address, @address)

    extra_args =
      Enum.map_join(extra, " ", fn
        {:nonce, v} -> ~s(nonce: "#{v}")
        {:message_hash, v} -> ~s(messageHash: "#{v}")
      end)

    mutation = """
    mutation {
      ethLogin(signature: "#{@signature}", address: "#{address}" #{extra_args}) {
        accessToken
        user { id ethAccounts { address } }
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end
end
