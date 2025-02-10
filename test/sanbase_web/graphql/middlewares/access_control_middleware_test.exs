defmodule SanbaseWeb.Graphql.AccessControlMiddlewareTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Accounts.Apikey

  setup do
    contract = "0x132123"
    # Both projects use the have same contract address for easier testing.
    # Accessing through the slug that is not "santiment" has timeframe restriction
    # while accessing through "santiment" does not
    p1 =
      insert(:random_erc20_project, %{
        slug: "santiment",
        main_contract_address: contract
      })

    p2 = insert(:random_erc20_project, %{main_contract_address: contract})

    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))

    conn = setup_jwt_auth(build_conn(), user)

    [
      conn: conn,
      santiment_slug: p1.slug,
      not_santiment_slug: p2.slug
    ]
  end

  test "`from` later than `to` datetime", context do
    query = """
     {
      gasUsed(
        slug: "santiment",
        from: "#{Timex.now()}",
        to: "#{Timex.shift(Timex.now(), days: -10)}"
        interval: "30m") {
          datetime
          gasUsed
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)

    %{
      "errors" => [
        %{
          "message" => error_message
        }
      ]
    } = result

    assert error_message =~
             "The `to` datetime parameter must be after the `from` datetime parameter"
  end

  test "returns error when `from` param is before 2009 year", context do
    query = """
     {
      gasUsed(
        slug: "santiment",
        from: "#{~U[2008-12-31 23:59:59Z]}",
        to: "#{~U[2009-01-02 00:00:00Z]}"
        interval: "1d") {
          datetime
          gasUsed
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query))

    error = List.first(json_response(result, 200)["errors"])["message"]

    assert error ==
             "Cryptocurrencies didn't exist before 2009-01-01 00:00:00Z.\nPlease check `from` and/or `to` parameters values.\n"
  end

  test "returns error when `from` and `to` params are both before 2009 year", context do
    query = """
     {
      gasUsed(
        slug: "santiment",
        from: "#{~U[2008-12-30 23:59:59Z]}",
        to: "#{~U[2008-12-31 23:59:59Z]}"
        interval: "1d") {
          datetime
          gasUsed
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query))

    error = List.first(json_response(result, 200)["errors"])["message"]

    assert error ==
             "Cryptocurrencies didn't exist before 2009-01-01 00:00:00Z.\nPlease check `from` and/or `to` parameters values.\n"
  end

  test "returns success when sansheets user with API key is Basic" do
    %{user: user} = insert(:subscription_basic_sanbase, user: insert(:user))
    {:ok, apikey} = Apikey.generate_apikey(user)

    conn =
      setup_apikey_auth(build_conn(), apikey)
      |> put_req_header(
        "user-agent",
        "Mozilla/5.0 (compatible; Google-Apps-Script)"
      )

    from = ~U[2019-01-01T00:00:00Z]
    to = ~U[2019-01-02T00:00:00Z]

    result = %{
      rows: [
        [DateTime.to_unix(from), 100],
        [DateTime.to_unix(to), 150]
      ]
    }

    query = """
     {
      getMetric(metric: "daily_active_addresses") {
        timeseriesData(
          slug: "santiment",
          from: "#{from}",
          to: "#{to}",
          interval: "1d") {
          datetime
          value
        }
      }
    }
    """

    Sanbase.Mock.prepare_mock2(
      &Sanbase.ClickhouseRepo.query/2,
      {:ok, result}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        conn
        |> post("/graphql", query_skeleton(query))
        |> json_response(200)

      assert Map.has_key?(result, "data") && !Map.has_key?(result, "error")
    end)
  end

  test "returns success when sansheets user with API key is Pro" do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    {:ok, apikey} = Apikey.generate_apikey(user)

    conn =
      setup_apikey_auth(build_conn(), apikey)
      |> put_req_header(
        "user-agent",
        "Mozilla/5.0 (compatible; Google-Apps-Script)"
      )

    from = ~U[2019-01-01 00:00:00Z]
    to = ~U[2019-01-02 00:00:00Z]

    result = %{
      rows: [
        [DateTime.to_unix(from), 100],
        [DateTime.to_unix(to), 150]
      ]
    }

    query = """
     {
      getMetric(metric: "daily_active_addresses") {
        timeseriesData(
          slug: "santiment",
          from: "#{from}",
          to: "#{to}",
          interval: "1d") {
          datetime
          value
        }
      }
    }
    """

    Sanbase.Mock.prepare_mock2(
      &Sanbase.ClickhouseRepo.query/2,
      {:ok, result}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        conn
        |> post("/graphql", query_skeleton(query))
        |> json_response(200)

      assert Map.has_key?(result, "data") && !Map.has_key?(result, "error")
    end)
  end

  test "returns error when sansheets user with API key is not Pro" do
    user = insert(:user, email: "a@example.com")
    {:ok, apikey} = Apikey.generate_apikey(user)

    conn =
      setup_apikey_auth(build_conn(), apikey)
      |> put_req_header(
        "user-agent",
        "Mozilla/5.0 (compatible; Google-Apps-Script)"
      )

    query = """
     {
      getMetric(metric: "social_volume_telegram") {
        timeseriesData(
          slug: "santiment",
          from: "#{Timex.shift(Timex.now(), days: -10)}",
          to: "#{Timex.now()}",
          interval: "1d") {
          datetime
          value
        }
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(401)

    assert result["errors"]["details"] ==
             """
             You need to upgrade Sanbase Pro in order to use SanSheets.
             If you already have Sanbase Pro, please make sure that a correct API key is provided.
             """
  end

  test "returns error when sansheets user without API key is not Pro" do
    insert(:user)

    conn =
      build_conn()
      |> put_req_header(
        "user-agent",
        "Mozilla/5.0 (compatible; Google-Apps-Script)"
      )

    query = """
    {
      getMetric(metric: "social_volume_telegram") {
        timeseriesData(
          slug: "santiment",
          from: "#{Timex.shift(Timex.now(), days: -10)}",
          to: "#{Timex.now()}",
          interval: "1d") {
          datetime
          value
        }
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(401)

    assert result["errors"]["details"] ==
             """
             You need to upgrade Sanbase Pro in order to use SanSheets.
             If you already have Sanbase Pro, please make sure that a correct API key is provided.
             """
  end

  describe "free experimental metrics access" do
    setup do
      project = insert(:random_erc20_project)
      from = Timex.shift(Timex.now(), days: -10)
      to = Timex.now()

      result = %{
        rows: [
          [DateTime.to_unix(from), 100],
          [DateTime.to_unix(to), 150]
        ]
      }

      query = fn metric_name ->
        """
        {
          getMetric(metric: "#{metric_name}") {
            timeseriesData(
              slug: "#{project.slug}",
              from: "#{from}",
              to: "#{to}",
              interval: "1d") {
              datetime
              value
            }
          }
        }
        """
      end

      [
        project: project,
        query: query,
        mock_result: result
      ]
    end

    test "beta metric can be accessed by alpha user", context do
      alpha_user = insert(:user, status: "alpha")
      conn = setup_jwt_auth(build_conn(), alpha_user)

      {:ok, metric} = Sanbase.Metric.Registry.by_name("price_usd_5m", "timeseries")
      {:ok, _} = Sanbase.Metric.Registry.update(metric, %{status: "beta"})

      Sanbase.Mock.prepare_mock2(
        &Sanbase.ClickhouseRepo.query/2,
        {:ok, context.mock_result}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          conn
          |> post("/graphql", query_skeleton(context.query.("price_usd_5m")))
          |> json_response(200)

        assert Map.has_key?(result, "data")
        refute Map.has_key?(result, "errors")
      end)
    end

    test "beta metric can be accessed by beta user", context do
      beta_user = insert(:user, status: "beta")
      conn = setup_jwt_auth(build_conn(), beta_user)

      {:ok, metric} = Sanbase.Metric.Registry.by_name("price_usd_5m", "timeseries")
      {:ok, _} = Sanbase.Metric.Registry.update(metric, %{status: "beta"})

      Sanbase.Mock.prepare_mock2(
        &Sanbase.ClickhouseRepo.query/2,
        {:ok, context.mock_result}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          conn
          |> post("/graphql", query_skeleton(context.query.("price_usd_5m")))
          |> json_response(200)

        assert Map.has_key?(result, "data")
        refute Map.has_key?(result, "errors")
      end)
    end

    test "beta metric cannot be accessed by regular user", context do
      regular_user = insert(:user, status: "regular")
      conn = setup_jwt_auth(build_conn(), regular_user)

      {:ok, metric} = Sanbase.Metric.Registry.by_name("price_usd_5m", "timeseries")
      {:ok, _} = Sanbase.Metric.Registry.update(metric, %{status: "beta"})

      result =
        conn
        |> post("/graphql", query_skeleton(context.query.("price_usd_5m")))
        |> json_response(200)

      assert %{
               "errors" => [
                 %{
                   "message" => error_message
                 }
               ]
             } = result

      assert error_message ==
               "This metric is in beta and is only available to alpha or beta users."
    end

    test "alpha metric cannot be accessed by beta user", context do
      beta_user = insert(:user, status: "beta")
      conn = setup_jwt_auth(build_conn(), beta_user)

      {:ok, metric} = Sanbase.Metric.Registry.by_name("price_usd_5m", "timeseries")
      {:ok, _} = Sanbase.Metric.Registry.update(metric, %{status: "alpha"})

      result =
        conn
        |> post("/graphql", query_skeleton(context.query.("price_usd_5m")))
        |> json_response(200)

      assert %{
               "errors" => [
                 %{
                   "message" => error_message
                 }
               ]
             } = result

      assert error_message == "This metric is in alpha and is only available to alpha users."
    end

    test "released free metrics can be accessed by any user", context do
      regular_user = insert(:user, status: "regular")
      conn = setup_jwt_auth(build_conn(), regular_user)

      {:ok, metric} = Sanbase.Metric.Registry.by_name("price_usd_5m", "timeseries")
      {:ok, _} = Sanbase.Metric.Registry.update(metric, %{status: "released"})

      Sanbase.Mock.prepare_mock2(
        &Sanbase.ClickhouseRepo.query/2,
        {:ok, context.mock_result}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          conn
          |> post("/graphql", query_skeleton(context.query.("price_usd_5m")))
          |> json_response(200)

        assert Map.has_key?(result, "data")
        refute Map.has_key?(result, "errors")
      end)
    end

    test "alpha metric can be accessed by alpha user", context do
      alpha_user = insert(:user, status: "alpha")
      conn = setup_jwt_auth(build_conn(), alpha_user)

      {:ok, metric} = Sanbase.Metric.Registry.by_name("price_usd_5m", "timeseries")
      {:ok, _} = Sanbase.Metric.Registry.update(metric, %{status: "alpha"})

      Sanbase.Mock.prepare_mock2(
        &Sanbase.ClickhouseRepo.query/2,
        {:ok, context.mock_result}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          conn
          |> post("/graphql", query_skeleton(context.query.("price_usd_5m")))
          |> json_response(200)

        assert Map.has_key?(result, "data")
        refute Map.has_key?(result, "errors")
      end)
    end
  end
end
