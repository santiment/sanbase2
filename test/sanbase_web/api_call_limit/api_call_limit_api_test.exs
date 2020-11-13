defmodule SanbaseWeb.ApiCallLimitTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  @remote_ip "91.246.248.228"

  setup do
    san_user = insert(:user, email: "santiment@santiment.net")
    {:ok, san_apikey} = Sanbase.Auth.Apikey.generate_apikey(san_user)
    san_apikey_conn = setup_apikey_auth(build_conn(), san_apikey)

    user = insert(:user, email: "santiment@gmail.com")
    {:ok, apikey} = Sanbase.Auth.Apikey.generate_apikey(user)
    apikey_conn = setup_apikey_auth(build_conn(), apikey)

    project = insert(:random_project)

    Sanbase.ApiCallLimit.ETS.clear_all()

    %{
      user: user,
      san_user: san_user,
      apikey_conn: apikey_conn,
      san_apikey_conn: san_apikey_conn,
      project: project
    }
  end

  describe "free apikey user" do
    test "make request before rate limit is applied", context do
      result =
        make_api_call(context.apikey_conn, [])
        |> json_response(200)

      assert result == %{"data" => %{"allProjects" => [%{"slug" => context.project.slug}]}}
    end

    test "make request after minute rate limit is applied", context do
      Sanbase.ApiCallLimit.update_usage(:user, context.user, 200, :apikey)

      response = make_api_call(context.apikey_conn, [{"x-forwarded-for", @remote_ip}])

      result =
        response
        |> json_response(429)

      %{"errors" => %{"details" => error_msg}} = result

      assert error_msg =~ "API Rate Limit Reached. Try again in"

      assert {"x-ratelimit-remaining-month", "800"} in response.resp_headers
      assert {"x-ratelimit-remaining-hour", "300"} in response.resp_headers
      assert {"x-ratelimit-remaining-minute", "0"} in response.resp_headers
      assert {"x-ratelimit-remaining", "0"} in response.resp_headers
    end

    test "make many requests before rate limit is applied", context do
      for _ <- 1..10, do: make_api_call(context.apikey_conn, [])

      result =
        make_api_call(context.apikey_conn, [])
        |> json_response(200)

      assert result == %{"data" => %{"allProjects" => [%{"slug" => context.project.slug}]}}
    end

    test "make request after hour rate limit is applied", context do
      Sanbase.ApiCallLimit.update_usage(:user, context.user, 600, :apikey)

      response = make_api_call(context.apikey_conn, [{"x-forwarded-for", @remote_ip}])

      result =
        response
        |> json_response(429)

      %{"errors" => %{"details" => error_msg}} = result

      assert error_msg =~ "API Rate Limit Reached. Try again in"

      assert {"x-ratelimit-remaining-month", "400"} in response.resp_headers
      assert {"x-ratelimit-remaining-hour", "0"} in response.resp_headers
      assert {"x-ratelimit-remaining-minute", "0"} in response.resp_headers
      assert {"x-ratelimit-remaining", "0"} in response.resp_headers
    end

    test "make many requests after rate limit is applied", context do
      Sanbase.ApiCallLimit.update_usage(:user, context.user, 1000, :apikey)
      for _ <- 1..10, do: make_api_call(context.apikey_conn, [])

      response = make_api_call(context.apikey_conn, [])

      result =
        response
        |> json_response(429)

      %{"errors" => %{"details" => error_msg}} = result

      assert error_msg =~ "API Rate Limit Reached. Try again in"

      assert {"x-ratelimit-remaining-month", "0"} in response.resp_headers
      assert {"x-ratelimit-remaining-hour", "0"} in response.resp_headers
      assert {"x-ratelimit-remaining-minute", "0"} in response.resp_headers
      assert {"x-ratelimit-remaining", "0"} in response.resp_headers
    end

    test "make request after month rate limit is applied", context do
      Sanbase.ApiCallLimit.update_usage(:user, context.user, 2000, :apikey)

      response = make_api_call(context.apikey_conn, [{"x-forwarded-for", @remote_ip}])

      result =
        response
        |> json_response(429)

      %{"errors" => %{"details" => error_msg}} = result

      assert error_msg =~ "API Rate Limit Reached. Try again in"

      assert {"x-ratelimit-remaining-month", "0"} in response.resp_headers
      assert {"x-ratelimit-remaining-hour", "0"} in response.resp_headers
      assert {"x-ratelimit-remaining-minute", "0"} in response.resp_headers
      assert {"x-ratelimit-remaining", "0"} in response.resp_headers
    end

    test "@santiment.net emails do not have limits", context do
      Sanbase.ApiCallLimit.update_usage(:user, context.san_user, 999_999_999, :apikey)

      response = make_api_call(context.san_apikey_conn, [{"x-forwarded-for", @remote_ip}])

      result =
        response
        |> json_response(200)

      assert result == %{"data" => %{"allProjects" => [%{"slug" => context.project.slug}]}}
    end
  end

  describe "paid apikey user" do
    test "pro sanapi subscription before rate limiting", context do
      insert(:subscription_pro, user: context.user)
      # 600/6_000/600_000 are the minute/hour/month rate limits
      Sanbase.ApiCallLimit.update_usage(:user, context.user, 500, :apikey)

      result =
        make_api_call(context.apikey_conn, [{"x-forwarded-for", @remote_ip}])
        |> json_response(200)

      assert result == %{"data" => %{"allProjects" => [%{"slug" => context.project.slug}]}}
    end

    test "pro sanapi subscription after rate limiting", context do
      insert(:subscription_pro, user: context.user)

      # 600/6_000/600_000 are the minute/hour/month rate limits
      Sanbase.ApiCallLimit.update_usage(:user, context.user, 700, :apikey)

      response = make_api_call(context.apikey_conn, [{"x-forwarded-for", @remote_ip}])

      result =
        response
        |> json_response(429)

      %{"errors" => %{"details" => error_msg}} = result

      assert error_msg =~ "API Rate Limit Reached. Try again in"

      assert {"x-ratelimit-remaining-month", "599300"} in response.resp_headers
      assert {"x-ratelimit-remaining-hour", "5300"} in response.resp_headers
      assert {"x-ratelimit-remaining-minute", "0"} in response.resp_headers
      assert {"x-ratelimit-remaining", "0"} in response.resp_headers
    end
  end

  describe "paid sanbase user" do
    test "make request before rate limit is applied", context do
      insert(:subscription_pro_sanbase, user: context.user)

      Sanbase.ApiCallLimit.update_usage(:user, context.user, 50, :apikey)

      result =
        make_api_call(context.apikey_conn, [])
        |> json_response(200)

      assert result == %{"data" => %{"allProjects" => [%{"slug" => context.project.slug}]}}
    end

    test "make request after minute rate limit is applied", context do
      insert(:subscription_pro_sanbase, user: context.user)
      Sanbase.ApiCallLimit.update_usage(:user, context.user, 200, :apikey)

      response = make_api_call(context.apikey_conn, [{"x-forwarded-for", @remote_ip}])

      result =
        response
        |> json_response(429)

      %{"errors" => %{"details" => error_msg}} = result

      assert error_msg =~ "API Rate Limit Reached. Try again in"

      assert {"x-ratelimit-remaining-month", "4800"} in response.resp_headers
      assert {"x-ratelimit-remaining-hour", "800"} in response.resp_headers
      assert {"x-ratelimit-remaining-minute", "0"} in response.resp_headers
      assert {"x-ratelimit-remaining", "0"} in response.resp_headers
    end
  end

  describe "no user - use remote ip" do
    test "ip address make request", context do
      # Use an IP address that is not a loopback or private
      result =
        make_api_call(context.conn, [{"x-forwarded-for", @remote_ip}])
        |> json_response(200)

      assert result == %{"data" => %{"allProjects" => [%{"slug" => context.project.slug}]}}
    end

    test "ip address cannot make request after quota is exhausted", context do
      Sanbase.ApiCallLimit.update_usage(:remote_ip, @remote_ip, 999_999_999, :unauthorized)

      response = make_api_call(context.conn, [{"x-forwarded-for", @remote_ip}])

      result =
        response
        |> json_response(429)

      %{"errors" => %{"details" => error_msg}} = result

      assert error_msg =~ "API Rate Limit Reached. Try again in"

      assert {"x-ratelimit-remaining-month", "0"} in response.resp_headers
      assert {"x-ratelimit-remaining-hour", "0"} in response.resp_headers
      assert {"x-ratelimit-remaining-minute", "0"} in response.resp_headers
      assert {"x-ratelimit-remaining", "0"} in response.resp_headers
    end
  end

  describe "subscribe while rate limited" do
    alias Sanbase.StripeApi
    alias Sanbase.StripeApiTestResponse, as: SATR

    test "subscribe while rate limited", context do
      Sanbase.Mock.prepare_mocks2([
        {&StripeApi.create_customer/2, SATR.create_or_update_customer_resp()},
        {&StripeApi.create_subscription/1, SATR.create_subscription_resp()}
      ])
      |> Sanbase.Mock.run_with_mocks(fn ->
        # Exhaust the minute and hour limits of the sanapi_free plan. The amount
        # should not exceed the minute limit of the sanapi_pro plan as it will get
        # ratelimited for the minute
        Sanbase.ApiCallLimit.update_usage(:user, context.user, 550, :apikey)

        response = make_api_call(context.apikey_conn, [{"x-forwarded-for", @remote_ip}])

        result =
          response
          |> json_response(429)

        %{"errors" => %{"details" => error_msg}} = result

        assert error_msg =~ "API Rate Limit Reached. Try again in"

        Sanbase.Billing.Subscription.subscribe(context.user, context.plans.plan_pro)

        response = make_api_call(context.apikey_conn, [{"x-forwarded-for", @remote_ip}])

        result =
          response
          |> json_response(200)

        assert result == %{"data" => %{"allProjects" => [%{"slug" => context.project.slug}]}}
      end)
    end
  end

  defp make_api_call(conn, extra_headers) do
    query = """
    { allProjects { slug } }
    """

    conn
    |> Sanbase.Utils.Conn.put_extra_req_headers(extra_headers)
    |> post("/graphql", query_skeleton(query))
  end
end
