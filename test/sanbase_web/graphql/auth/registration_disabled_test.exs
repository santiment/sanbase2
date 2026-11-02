defmodule SanbaseWeb.Graphql.RegistrationDisabledTest do
  # Mock (meck) replaces modules globally, so these tests cannot be async.
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory
  import ExUnit.CaptureLog

  alias Sanbase.Accounts.User
  alias Sanbase.FeatureToggle
  alias Sanbase.Billing.Subscription.LiquiditySubscription

  @message "New registrations are temporarily disabled."

  # Unused Ropsten testnet address. The signature check is mocked.
  @address "0x9024d48cc7be15343dfd76ef051fa5264cfbf7a9"
  @message_hash "0xff8ca2965b505cabd1156342c1dfa72c11e7c5e00ff839a12af71e8a7d231731"
  @signature "0xeba4d1a091ca6e7cb0_signature_check_will_be_mocked"

  describe "feature toggle" do
    test "registration is enabled when there is no row" do
      refute FeatureToggle.user_registration_disabled?()
      assert {:ok, %User{}} = User.find_or_insert_by(:email, "new@example.com")
    end

    test "a row inserted directly in the DB disables registration" do
      Sanbase.Repo.insert!(%FeatureToggle{name: "disable_user_registration", enabled: true})

      assert FeatureToggle.user_registration_disabled?()

      assert {:error, :registrations_disabled} =
               User.find_or_insert_by(:email, "new@example.com")
    end

    test "disable and enable registration" do
      {:ok, _} = FeatureToggle.disable_user_registration()
      assert FeatureToggle.user_registration_disabled?()
      assert {:error, :registrations_disabled} = User.create(%{email: "new@example.com"})

      {:ok, _} = FeatureToggle.enable_user_registration()
      refute FeatureToggle.user_registration_disabled?()
      assert {:ok, %User{}} = User.create(%{email: "new@example.com"})
    end

    test "setting a toggle twice updates the same row" do
      {:ok, _} = FeatureToggle.disable_user_registration()
      {:ok, _} = FeatureToggle.enable_user_registration()
      {:ok, toggle} = FeatureToggle.disable_user_registration()

      assert toggle.enabled
      assert [%FeatureToggle{enabled: true}] = Sanbase.Repo.all(FeatureToggle)
    end

    test "internal tooling can create users with skip_registration_check" do
      {:ok, _} = FeatureToggle.disable_user_registration()

      assert {:ok, %User{}} =
               User.find_or_insert_by(:email, "tool@example.com", %{},
                 skip_registration_check: true
               )
    end

    test "existing users are still found when registration is disabled" do
      user = insert(:user, email: "existing@example.com")
      {:ok, _} = FeatureToggle.disable_user_registration()

      assert {:ok, %User{id: id}} = User.find_or_insert_by(:email, "existing@example.com")
      assert id == user.id
    end
  end

  describe "email login with registration disabled" do
    setup_with_mocks([
      {Sanbase.TemplateMailer, [], [send: fn _, _, _ -> {:ok, %{}} end]},
      {Sanbase.Accounts.Turnstile, [], [validate: fn _, _ -> :ok end]}
    ]) do
      {:ok, _} = FeatureToggle.disable_user_registration()
      []
    end

    test "a new email gets the same response as an existing one, but no user or email",
         context do
      log =
        capture_log(fn ->
          result =
            context.conn
            |> Plug.Conn.put_req_header("origin", "https://app.santiment.net")
            |> email_login(%{email: "new@example.com", token: "test-token"})

          assert result == %{"data" => %{"emailLogin" => %{"success" => true}}}
        end)

      assert log =~ "registrations are disabled"
      assert {:error, _} = User.by_email("new@example.com")
      assert call_history(Sanbase.TemplateMailer) == []
    end

    test "an existing user still gets a login email", context do
      insert(:user, email: "existing@example.com")

      result =
        context.conn
        |> Plug.Conn.put_req_header("origin", "https://app.santiment.net")
        |> email_login(%{email: "existing@example.com", token: "test-token"})
        |> get_in(["data", "emailLogin"])

      assert result["success"]
    end
  end

  describe "eth login with registration disabled" do
    setup do
      {:ok, _} = FeatureToggle.disable_user_registration()
      :ok
    end

    test "a new address gets an error and no user is created", context do
      users_count_before = Sanbase.Repo.aggregate(User, :count)

      Sanbase.Mock.prepare_mock2(&Sanbase.InternalServices.Ethauth.valid_signature?/2, true)
      |> Sanbase.Mock.run_with_mocks(fn ->
        log =
          capture_log(fn ->
            error_msg =
              eth_login(context.conn)
              |> get_in(["errors", Access.at(0), "message"])

            assert error_msg == @message
          end)

        assert log =~ "registrations are disabled"
      end)

      assert Sanbase.Repo.aggregate(User, :count) == users_count_before
      assert Sanbase.Accounts.EthAccount.by_address(@address) == nil
    end

    test "an existing address can still log in", context do
      {:ok, _} = FeatureToggle.enable_user_registration()
      {:ok, user} = Sanbase.Accounts.create_user_with_eth_address(@address)
      {:ok, _} = FeatureToggle.disable_user_registration()

      Sanbase.Mock.prepare_mock2(&Sanbase.InternalServices.Ethauth.valid_signature?/2, true)
      |> Sanbase.Mock.prepare_mock2(&LiquiditySubscription.user_staked_in_uniswap_v2/1, false)
      |> Sanbase.Mock.prepare_mock2(&LiquiditySubscription.user_staked_in_uniswap_v3/1, false)
      |> Sanbase.Mock.run_with_mocks(fn ->
        result = eth_login(context.conn) |> get_in(["data", "ethLogin"])

        assert result["user"]["id"] == to_string(user.id)
        assert is_binary(result["accessToken"])
      end)
    end
  end

  defp email_login(conn, args) do
    mutation = """
    mutation {
      emailLogin(#{map_to_args(args)}) {
        success
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  defp eth_login(conn) do
    mutation = """
    mutation {
      ethLogin(
        signature: "#{@signature}"
        address: "#{@address}"
        messageHash: "#{@message_hash}"){
          user{ id }
          accessToken
        }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end
end
