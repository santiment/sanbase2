defmodule SanbaseWeb.Graphql.AuthPlugDbQueriesTest do
  # Pins what AuthPlug resolves for an authenticated request (user, chosen
  # subscription, plan name, permissions) and how many Postgres queries it takes.
  # Serial because the query counter is a global telemetry handler.
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Accounts.{Apikey, EthAccount, UserRole}
  alias Sanbase.Billing.{Plan, Product, Subscription}
  alias Sanbase.Insight.PostPaywall
  alias Sanbase.Repo
  alias SanbaseWeb.Graphql.AuthPlug

  @sansheets_user_agent "Sansheets/1.0"
  @warm_auth_queries 2

  describe "apikey authentication" do
    test "user without a subscription" do
      user = insert(:user)

      auth = assert_warm_queries(apikey_conn_fun(user))

      assert auth.auth.auth_method == :apikey
      assert auth.auth.current_user.id == user.id
      assert auth.auth.subscription == nil
      assert auth.auth.plan == "FREE"
      assert auth.requested_product == "SANAPI"
      assert auth.subscription_product_id == nil
      assert auth.subscription_product == nil
      assert auth.permissions == %{api: false, sanbase: false, spreadsheet: false}
    end

    test "SanAPI subscription" do
      user = insert(:user)
      sub = insert(:subscription_business_pro_monthly, user: user)

      auth = assert_warm_queries(apikey_conn_fun(user))

      assert auth.auth.subscription.id == sub.id
      assert auth.auth.subscription.plan.product.id == auth.subscription_product_id
      assert auth.auth.plan == "BUSINESS_PRO"
      assert auth.subscription_product == "SANAPI"
      assert auth.permissions == %{api: true, sanbase: true, spreadsheet: true}
    end

    test "Sanbase-only subscription falls back for a SanAPI request" do
      user = insert(:user)
      sub = insert(:subscription_pro_sanbase, user: user)

      auth = assert_warm_queries(apikey_conn_fun(user))

      assert auth.auth.subscription.id == sub.id
      assert auth.auth.plan == "PRO"
      assert auth.requested_product == "SANAPI"
      assert auth.subscription_product == "SANBASE"
      assert auth.permissions == %{api: true, sanbase: true, spreadsheet: true}
    end

    test "both products: each request picks its own product's subscription" do
      user = insert(:user)
      api_sub = insert(:subscription_business_max_monthly, user: user)
      sanbase_sub = insert(:subscription_max_sanbase, user: user)

      auth = assert_warm_queries(apikey_conn_fun(user))
      assert auth.auth.subscription.id == api_sub.id
      assert auth.auth.plan == "BUSINESS_MAX"
      assert auth.subscription_product == "SANAPI"

      auth = assert_warm_queries(apikey_conn_fun(user, @sansheets_user_agent))
      assert auth.auth.subscription.id == sanbase_sub.id
      assert auth.auth.plan == "MAX"
      assert auth.requested_product == "SANBASE"
      assert auth.subscription_product == "SANBASE"
    end

    test "SanAPI-only subscription falls back for a Sansheets request" do
      user = insert(:user)
      sub = insert(:subscription_business_pro_monthly, user: user)

      auth = assert_warm_queries(apikey_conn_fun(user, @sansheets_user_agent))

      assert auth.auth.subscription.id == sub.id
      assert auth.auth.plan == "BUSINESS_PRO"
      assert auth.requested_product == "SANBASE"
      assert auth.subscription_product == "SANAPI"
    end

    test "custom plan: raw name for SanAPI, restricted_access_as_plan for Sanbase", context do
      user = insert(:user)
      plan = create_custom_api_plan(context)
      sub = insert(:subscription, user: user, plan_id: plan.id)

      auth = assert_warm_queries(apikey_conn_fun(user))
      assert auth.auth.subscription.id == sub.id
      assert auth.auth.plan == "CUSTOM_DB_QUERIES_PLAN"

      auth = assert_warm_queries(apikey_conn_fun(user, @sansheets_user_agent))
      assert auth.auth.subscription.id == sub.id
      assert auth.auth.plan == "PRO"
    end

    test "two subscriptions for one product: the highest id wins" do
      user = insert(:user)
      _older = insert(:subscription_business_pro_monthly, user: user)
      newer = insert(:subscription_business_max_monthly, user: user)

      auth = assert_warm_queries(apikey_conn_fun(user))

      assert auth.auth.subscription.id == newer.id
      assert auth.auth.plan == "BUSINESS_MAX"
    end

    test "trialing and past_due subscriptions count" do
      for status <- ["trialing", "past_due"] do
        user = insert(:user)
        sub = insert(:subscription_business_pro_monthly, user: user, status: status)

        auth = assert_warm_queries(apikey_conn_fun(user))

        assert auth.auth.subscription.id == sub.id, "status #{status}"
        assert auth.permissions == %{api: true, sanbase: true, spreadsheet: true}
      end
    end

    test "canceled, incomplete, incomplete_expired and unpaid subscriptions do not count" do
      for status <- ["canceled", "incomplete", "incomplete_expired", "unpaid"] do
        user = insert(:user)
        _sub = insert(:subscription_business_pro_monthly, user: user, status: status)

        auth = assert_warm_queries(apikey_conn_fun(user))

        assert auth.auth.subscription == nil, "status #{status}"
        assert auth.auth.plan == "FREE"
        assert auth.permissions == %{api: false, sanbase: false, spreadsheet: false}
      end
    end

    test "loads roles, eth accounts and settings without duplicates" do
      user = insert(:user)
      insert(:user_settings, user: user)
      role1 = insert(:role_san_family)
      role2 = insert(:role_san_moderator)
      Repo.insert!(%UserRole{user_id: user.id, role_id: role1.id})
      Repo.insert!(%UserRole{user_id: user.id, role_id: role2.id})
      Repo.insert!(%EthAccount{user_id: user.id, address: "0x1"})
      Repo.insert!(%EthAccount{user_id: user.id, address: "0x2"})

      auth = assert_warm_queries(apikey_conn_fun(user))
      current_user = auth.auth.current_user

      assert current_user.roles |> Enum.map(& &1.role.name) |> Enum.sort() ==
               Enum.sort([role1.name, role2.name])

      assert current_user.eth_accounts |> Enum.map(& &1.address) |> Enum.sort() ==
               ["0x1", "0x2"]

      assert current_user.user_settings.user_id == user.id
    end
  end

  describe "JWT authentication" do
    test "session token: Sanbase subscription preferred" do
      user = insert(:user)
      _api_sub = insert(:subscription_business_pro_monthly, user: user)
      sanbase_sub = insert(:subscription_pro_sanbase, user: user)

      auth = assert_warm_queries(jwt_session_conn_fun(user))

      assert auth.auth.auth_method == :user_token
      assert auth.auth.current_user.id == user.id
      assert auth.auth.subscription.id == sanbase_sub.id
      assert auth.auth.plan == "PRO"
      assert auth.requested_product == "SANBASE"
      assert auth.subscription_product == "SANBASE"
      assert auth.permissions == %{api: true, sanbase: true, spreadsheet: true}
    end

    test "session token: falls back to the SanAPI subscription" do
      user = insert(:user)
      api_sub = insert(:subscription_business_pro_monthly, user: user)

      auth = assert_warm_queries(jwt_session_conn_fun(user))

      assert auth.auth.subscription.id == api_sub.id
      assert auth.auth.plan == "BUSINESS_PRO"
      assert auth.subscription_product == "SANAPI"
    end

    test "session token: user without a subscription" do
      user = insert(:user)

      auth = assert_warm_queries(jwt_session_conn_fun(user))

      assert auth.auth.subscription == nil
      assert auth.auth.plan == "FREE"
      assert auth.permissions == %{api: false, sanbase: false, spreadsheet: false}
    end

    test "bearer header: Sanbase subscription preferred, SanAPI fallback" do
      user = insert(:user)
      api_sub = insert(:subscription_business_pro_monthly, user: user)

      auth = assert_warm_queries(jwt_bearer_conn_fun(user))
      assert auth.auth.subscription.id == api_sub.id
      assert auth.auth.plan == "BUSINESS_PRO"
      assert auth.requested_product == "SANBASE"

      sanbase_sub = insert(:subscription_pro_sanbase, user: user)

      auth = assert_warm_queries(jwt_bearer_conn_fun(user))
      assert auth.auth.subscription.id == sanbase_sub.id
      assert auth.auth.plan == "PRO"
      assert auth.permissions == %{api: true, sanbase: true, spreadsheet: true}
    end
  end

  describe "reusing the subscriptions loaded by the auth plug" do
    test "current_subscription_from_auth/2 answers from the auth map without queries" do
      user = insert(:user)
      api_sub = insert(:subscription_business_pro_monthly, user: user)
      sanbase_sub = insert(:subscription_pro_sanbase, user: user)

      auth = authenticate(apikey_conn_fun(user).()).auth

      {result, sources} =
        count_queries(fn ->
          {Subscription.current_subscription_from_auth(auth, Product.product_api()),
           Subscription.current_subscription_from_auth(auth, Product.product_sanbase()),
           Subscription.current_subscription_from_auth(auth, 999)}
        end)

      assert sources == []
      assert {%Subscription{id: api_id}, %Subscription{id: sanbase_id}, nil} = result
      assert api_id == api_sub.id
      assert sanbase_id == sanbase_sub.id
    end

    test "current_subscription_from_auth/2 falls back to a query without the auth map" do
      user = insert(:user)
      api_sub = insert(:subscription_business_pro_monthly, user: user)

      {result, sources} =
        count_queries(fn ->
          Subscription.current_subscription_from_auth(
            %{current_user: user},
            Product.product_api()
          )
        end)

      assert result.id == api_sub.id
      assert sources != []
    end

    test "the paywall filter makes no subscription queries" do
      user = insert(:user)
      insert(:subscription_pro_sanbase, user: user)
      text = Stream.cycle(["word"]) |> Enum.take(200) |> Enum.join(" ")
      post = build(:post, user_id: insert(:user).id, text: text, is_paywall_required: true)

      auth = authenticate(jwt_session_conn_fun(user).()).auth

      {[filtered], sources} =
        count_queries(fn -> PostPaywall.maybe_filter_paywalled([post], auth) end)

      assert sources == []
      assert filtered.text == text

      free_auth = authenticate(jwt_session_conn_fun(insert(:user)).()).auth

      {[filtered], sources} =
        count_queries(fn -> PostPaywall.maybe_filter_paywalled([post], free_auth) end)

      assert sources == []
      assert filtered.text != text
    end
  end

  # Helpers

  defp apikey_conn_fun(user, user_agent \\ nil) do
    {:ok, apikey} = Apikey.generate_apikey(user)

    fn ->
      conn = build_conn() |> setup_apikey_auth(apikey)

      case user_agent do
        nil -> conn
        ua -> Plug.Conn.put_req_header(conn, "user-agent", ua)
      end
    end
  end

  defp jwt_session_conn_fun(user) do
    {:ok, tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)
    fn -> Plug.Test.init_test_session(build_conn(), tokens) end
  end

  defp jwt_bearer_conn_fun(user) do
    {:ok, %{access_token: access_token}} = SanbaseWeb.Guardian.get_jwt_tokens(user)

    fn ->
      build_conn()
      |> Plug.Conn.put_req_header("authorization", "Bearer " <> access_token)
    end
  end

  # Authenticates once to warm per-node caches, then authenticates again and
  # asserts the number of queries the second call makes.
  defp assert_warm_queries(conn_fun) do
    _ = authenticate(conn_fun.())
    {auth, sources} = count_queries(fn -> authenticate(conn_fun.()) end)

    assert length(sources) == @warm_auth_queries,
           "expected #{@warm_auth_queries} queries, got #{length(sources)}: #{inspect(sources)}"

    auth
  end

  defp authenticate(conn) do
    conn =
      conn
      |> then(fn conn ->
        if Map.has_key?(conn.private, :plug_session),
          do: conn,
          else: Plug.Test.init_test_session(conn, %{})
      end)
      |> AuthPlug.call(%{})

    refute conn.halted
    conn.private.san_authentication
  end

  defp count_queries(fun) do
    handler_id = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler_id,
        [:sanbase, :repo, :query],
        &__MODULE__.handle_query_event/4,
        self()
      )

    try do
      result = fun.()
      {result, collect_queries([])}
    after
      :telemetry.detach(handler_id)
    end
  end

  # Counts only queries made by the test process or processes it spawned (preloads
  # run in tasks that carry the test process in $callers).
  def handle_query_event(_event, _measurements, metadata, test_pid) do
    if test_pid in [self() | Process.get(:"$callers", [])] do
      send(test_pid, {:repo_query, metadata[:source] || "raw"})
    end
  end

  defp collect_queries(acc) do
    receive do
      {:repo_query, source} -> collect_queries([source | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp create_custom_api_plan(context) do
    Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 1001")

    {:ok, plan} =
      Plan.create_custom_api_plan(%{
        id: 1000,
        name: "CUSTOM_DB_QUERIES_PLAN",
        product_id: context.product_api.id,
        stripe_id: context.product_api.stripe_id,
        amount: 35_900,
        currency: "USD",
        interval: "month",
        restrictions: %{
          name: "CUSTOM_DB_QUERIES_PLAN",
          restricted_access_as_plan: "PRO",
          requested_product: "SANAPI",
          api_call_limits: %{"minute" => 1000, "hour" => 100_000, "month" => 3_000_000},
          historical_data_in_days: 365,
          realtime_data_cut_off_in_days: 0,
          metric_access: %{"accessible" => "all", "not_accessible" => []},
          query_access: %{"accessible" => "all", "not_accessible" => []},
          signal_access: %{"accessible" => "all", "not_accessible" => []}
        }
      })

    plan
  end
end
