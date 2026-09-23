defmodule SanbaseWeb.Graphql.ApiMetricVersionAccessTest do
  @moduledoc ~s"""
  Metric version access: apikey calls get their plan's SanAPI rules, anonymous calls
  get version 1.0 only, JWT and basic auth are not restricted. Headers the caller
  controls (Origin, User-Agent) never change the answer.
  """
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.MetricVersionAliasHelpers, only: [create_alias!: 1]

  alias Sanbase.Accounts.Apikey
  alias Sanbase.Metric.VersionAlias

  @metric "daily_active_addresses"
  @sansheets_user_agent "Mozilla/5.0 (compatible; Google-Apps-Script)"

  setup do
    VersionAlias.clear_cache()
    :ok
  end

  describe "apikey" do
    test "Sanbase MAX gets version 1.0 only" do
      conn = apikey_conn(:subscription_max_sanbase)

      assert allowed?(conn, "1.0")
      assert denied?(conn, "2.0")
      assert denied?(conn, "2.1")
      assert denied?(conn, "3.0")
    end

    test "Business Pro gets the newer versions but not point-in-time" do
      for factory <- [:subscription_business_pro_monthly, :subscription_business_pro_yearly] do
        conn = apikey_conn(factory)

        assert allowed?(conn, "1.0")
        assert allowed?(conn, "2.0")
        assert allowed?(conn, "3.0")
        assert denied?(conn, "2.1")
        assert denied?(conn, "2.1.1")
        assert denied?(conn, "3.1")
      end
    end

    test "Business Max monthly gets the newer versions but not point-in-time" do
      conn = apikey_conn(:subscription_business_max_monthly)

      assert allowed?(conn, "2.0")
      assert denied?(conn, "2.1")
    end

    test "Business Max yearly gets every version" do
      conn = apikey_conn(:subscription_business_max_yearly)

      for version <- ["1.0", "2.0", "2.1", "2.1.2", "3.0", "3.1"] do
        assert allowed?(conn, version), version
      end
    end

    test "a Business Max yearly trial does not get point-in-time" do
      conn = apikey_conn(:subscription_business_max_yearly, status: "trialing")

      assert allowed?(conn, "2.0")
      assert denied?(conn, "2.1")
    end

    test "no subscription gets version 1.0 only" do
      {:ok, apikey} = Apikey.generate_apikey(insert(:user))
      conn = setup_apikey_auth(build_conn(), apikey)

      assert allowed?(conn, "1.0")
      assert denied?(conn, "2.0")
    end

    test "omitting the version is unaffected" do
      conn = apikey_conn(:subscription_max_sanbase)
      assert allowed?(conn, nil)
    end

    test "a version name is checked as its canonical number" do
      # Not the seeded 2.x aliases, which a migrated test database already has.
      create_alias!(%{version_num: "7.0", version_name: "seven:v1"})
      create_alias!(%{version_num: "7.1", version_name: "seven_pit:v1"})
      conn = apikey_conn(:subscription_business_max_monthly)

      assert allowed?(conn, "seven:v1")
      assert denied?(conn, "seven_pit:v1")
    end

    test "the error uses version names and names the required and the current plan" do
      ensure_seeded_aliases()
      conn = apikey_conn(:subscription_business_max_monthly)

      # Same message whether the number or the name was requested.
      for version <- ["2.1", "modern_pit:v1"] do
        error = execute_query_with_error(conn, query(version), "getMetric")

        assert error ==
                 "Metric version modern_pit:v1 requires a paid yearly SanAPI Business Max " <>
                   "subscription. Your plan (BUSINESS_MAX, month) has access to " <>
                   "original:v1, modern:v1, stock:v1."
      end
    end

    test "a version without a name is shown as its number" do
      conn = apikey_conn(:subscription_max_sanbase)

      error = execute_query_with_error(conn, query("9.1"), "getMetric")

      assert error =~ "Metric version 9.1 requires a paid yearly SanAPI Business Max"
    end

    test "the user agent does not change the rules - Sansheets gets the plan's API rules" do
      sansheets = &put_req_header(&1, "user-agent", @sansheets_user_agent)

      # Sanbase MAX in Sansheets: same as its apikey anywhere else.
      assert denied?(sansheets.(apikey_conn(:subscription_max_sanbase)), "2.0")

      # A paying API customer keeps their access in Sansheets.
      assert allowed?(sansheets.(apikey_conn(:subscription_business_max_yearly)), "2.1")
    end

    test "Sansheets judges the key by the SanAPI subscription when there are both" do
      %{user: user} = insert(:subscription_business_max_yearly, user: insert(:user))
      insert(:subscription_max_sanbase, user: user)
      {:ok, apikey} = Apikey.generate_apikey(user)

      conn =
        build_conn()
        |> setup_apikey_auth(apikey)
        |> put_req_header("user-agent", @sansheets_user_agent)

      assert allowed?(conn, "2.1")
    end
  end

  describe "anonymous" do
    test "without an origin gets version 1.0 only" do
      assert allowed?(build_conn(), "1.0")
      assert denied?(build_conn(), "2.0")
    end

    test "from a third-party origin gets version 1.0 only" do
      conn = put_req_header(build_conn(), "origin", "https://example.com")
      assert denied?(conn, "2.0")
    end

    test "the origin does not change the rules - a Santiment origin gets version 1.0 only" do
      conn = put_req_header(build_conn(), "origin", "https://app.santiment.net")

      assert allowed?(conn, "1.0")
      assert denied?(conn, "2.0")
    end

    test "the error says anonymous requests have version 1.0 only" do
      ensure_seeded_aliases()

      assert execute_query_with_error(build_conn(), query("2.0"), "getMetric") ==
               "Metric version modern:v1 requires a SanAPI Business Pro or Business Max " <>
                 "subscription. Anonymous requests have access to original:v1."
    end
  end

  describe "not restricted" do
    test "JWT (the Sanbase web app)" do
      %{user: user} = insert(:subscription_max_sanbase, user: insert(:user))
      conn = setup_jwt_auth(build_conn(), user)

      assert allowed?(conn, "2.0")
      assert allowed?(conn, "2.1")
    end

    test "basic auth" do
      conn = setup_basic_auth(build_conn(), "user", "pass")
      assert allowed?(conn, "2.1")
    end
  end

  test "while enforcement is off, a request that would be denied is allowed" do
    conn = apikey_conn(:subscription_max_sanbase)
    config = Application.get_env(:sanbase, Sanbase.Billing.Plan.MetricVersionAccess)

    try do
      Application.put_env(:sanbase, Sanbase.Billing.Plan.MetricVersionAccess, enforce: false)
      assert allowed?(conn, "2.1")
    after
      Application.put_env(:sanbase, Sanbase.Billing.Plan.MetricVersionAccess, config)
    end
  end

  # The rows the migration seeds. A migrated test database already has them, one
  # loaded from structure.sql does not.
  defp ensure_seeded_aliases() do
    for {num, name} <- [
          {"1.0", "original:v1"},
          {"2.0", "modern:v1"},
          {"2.1", "modern_pit:v1"},
          {"3.0", "stock:v1"},
          {"3.1", "stock_pit:v1"}
        ],
        is_nil(Sanbase.Repo.get_by(VersionAlias, version_num: num)) do
      create_alias!(%{version_num: num, version_name: name})
    end

    VersionAlias.clear_cache()
  end

  defp apikey_conn(factory, attrs \\ []) do
    %{user: user} = insert(factory, Keyword.merge([user: insert(:user)], attrs))
    {:ok, apikey} = Apikey.generate_apikey(user)
    setup_apikey_auth(build_conn(), apikey)
  end

  defp allowed?(conn, version) do
    match?(
      %{"data" => %{"getMetric" => %{"metadata" => %{"metric" => @metric}}}},
      execute_query(conn, query(version))
    )
  end

  defp denied?(conn, version) do
    case execute_query(conn, query(version)) do
      %{"errors" => [%{"message" => "Metric version " <> _}]} -> true
      _ -> false
    end
  end

  defp query(version) do
    version_arg = if version, do: ~s(, version: "#{version}"), else: ""

    """
    {
      getMetric(metric: "#{@metric}"#{version_arg}) {
        metadata { metric }
      }
    }
    """
  end
end
