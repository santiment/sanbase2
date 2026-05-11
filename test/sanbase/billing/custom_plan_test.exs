defmodule Sanbase.Billing.Plan.CustomPlanTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup context do
    # The rest of the plans are inserted with hardcoded ids. Because of this
    # the plans_id_seq will generate id 1, which will cause a constraint error
    Sanbase.Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 1001")
    {:ok, plan} = create_custom_api_plan(context)
    # TODO: Sometimes the daily_active_addresses being beta access bleeds in here
    user = insert(:user, metric_access_level: "alpha")
    _sub = insert(:subscription, user: user, plan_id: plan.id)
    {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)
    conn = setup_apikey_auth(build_conn(), apikey)

    %{
      plan: plan,
      user: user,
      conn: conn
    }
  end

  test "create custom plan", context do
    %{plan: plan} = context

    %{
      resolved_metrics: resolved_metrics,
      resolved_queries: resolved_queries,
      resolved_signals: resolved_signals,
      restrictions: _restrictions
    } =
      Sanbase.Billing.Plan.CustomPlan.Loader.get_data(
        plan.name,
        Sanbase.Billing.Product.code_by_id(plan.product_id)
      )

    assert "price_usd" in resolved_metrics
    assert "active_addresses_24h" in resolved_metrics
    assert "social_volume_total" in resolved_metrics
    assert "daily_active_addresses" not in resolved_metrics
    assert not Enum.any?(resolved_metrics, fn metric -> String.contains?(metric, "mvrv_usd") end)

    assert "current_user" in resolved_queries
    assert "all_projects" in resolved_queries
    assert "project_by_slug" in resolved_queries
    assert "history_price" not in resolved_queries
    assert not Enum.any?(resolved_queries, fn query -> String.contains?(query, "mvrv") end)

    assert Enum.sort(resolved_signals) ==
             Enum.sort(Sanbase.Signal.free_signals() ++ Sanbase.Signal.restricted_signals())

    assert resolved_metrics ==
             Sanbase.Billing.Plan.AccessChecker.get_available_metrics_for_plan(
               plan.name,
               "SANAPI",
               :all
             )

    assert %{
             "month" => 3_000_000,
             "hour" => 100_000,
             "minute" => 1000
           } ==
             Sanbase.Billing.Plan.CustomPlan.Access.api_call_limits(
               plan.name,
               Sanbase.Billing.Product.code_by_id(plan.product_id)
             )
  end

  test "custom plan access is cut to some metrics", context do
    %{conn: conn} = context

    project = insert(:random_project)

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: []}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      # mvrv_usd metrics are not accessible because of the pattern
      assert %{"errors" => [error]} = get_metric(conn, "mvrv_usd")

      assert error["message"] =~
               "metric mvrv_usd is not included in the currently used SANAPI CUSTOM_API_PLAN plan"

      assert %{"errors" => [error]} = get_metric(conn, "daily_active_addresses")

      # mvrv_usd metrics are not accessible because of the explicit list
      assert error["message"] =~
               "metric daily_active_addresses is not included in the currently used SANAPI CUSTOM_API_PLAN plan"

      # nvt is accessible
      assert get_metric(conn, "nvt", slug: project.slug, from: "utc_now-300d", to: "utc_now") ==
               %{
                 "data" => %{"getMetric" => %{"timeseriesData" => []}}
               }

      assert %{"errors" => [error]} =
               get_metric(conn, "nvt", from: "utc_now-370d", to: "utc_now-369d")

      assert error["message"] =~ "outside the allowed interval you can query"
    end)
  end

  test "custom plan access is cut to some queries", context do
    %{conn: conn, user: user} = context
    user_id = user.id |> to_string()

    assert %{"errors" => [error]} = get_history_price(conn)

    assert error["message"] =~
             "query history_price is not included in the currently used SANAPI CUSTOM_API_PLAN plan"

    assert %{"data" => %{"currentUser" => %{"id" => ^user_id}}} = get_current_user(conn)

    assert %{"errors" => [error]} =
             get_metric(conn, "nvt", from: "utc_now-370d", to: "utc_now-369d")

    assert error["message"] =~ "outside the allowed interval you can query"
  end

  test "alpha metric cannot be accessed by user without alpha access", context do
    %{plan: plan} = context

    # Create a user without alpha access and subscribe them to the custom plan
    non_alpha_user = insert(:user, metric_access_level: "released")
    _sub = insert(:subscription, user: non_alpha_user, plan_id: plan.id)
    {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(non_alpha_user)
    conn = setup_apikey_auth(build_conn(), apikey)

    # Create a temporary metric with alpha status
    {:ok, registry} =
      Sanbase.Metric.Registry.create(%{
        metric: "random_metric_alpha_access",
        internal_metric: "random_metric_alpha_access",
        human_readable_name: "Random Metric Alpha Access",
        min_interval: "5m",
        default_aggregation: "avg",
        access: "free",
        has_incomplete_data: false,
        data_type: "timeseries",
        status: "alpha",
        sanbase_min_plan: "free",
        sanapi_min_plan: "free",
        tables: [%{name: "daily_metrics_v2"}]
      })

    Sanbase.Metric.Registry.refresh_stored_terms()

    try do
      assert %{"errors" => [error]} = get_metric(conn, "random_metric_alpha_access")

      assert error["message"] ==
               "The metric random_metric_alpha_access is currently in alpha phase and is exclusively available to alpha users."
    after
      {:ok, _} = Sanbase.Metric.Registry.delete(registry)
      Sanbase.Metric.Registry.refresh_stored_terms()
    end
  end

  describe "validation" do
    test "rejects malformed regex in not_accessible_patterns", context do
      Sanbase.Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 9001")

      result =
        Sanbase.Billing.Plan.create_custom_api_plan(%{
          id: 9000,
          name: "CUSTOM_BAD_REGEX",
          product_id: context.product_api.id,
          stripe_id: context.product_api.stripe_id,
          restrictions: %{
            restricted_access_as_plan: "PRO",
            api_call_limits: %{"minute" => 100, "hour" => 1000, "month" => 10_000},
            metric_access: %{
              "accessible" => "all",
              "not_accessible" => [],
              "not_accessible_patterns" => ["(unclosed"]
            },
            query_access: %{
              "accessible" => "all",
              "not_accessible" => [],
              "not_accessible_patterns" => []
            },
            signal_access: %{
              "accessible" => "all",
              "not_accessible" => [],
              "not_accessible_patterns" => []
            }
          },
          amount: 10_000,
          currency: "USD",
          interval: "month"
        })

      assert {:error, %Ecto.Changeset{}} = result
    end

    test "rejects malformed regex in accessible_patterns", context do
      Sanbase.Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 9101")

      result =
        Sanbase.Billing.Plan.create_custom_api_plan(%{
          id: 9100,
          name: "CUSTOM_BAD_REGEX2",
          product_id: context.product_api.id,
          stripe_id: context.product_api.stripe_id,
          restrictions: %{
            restricted_access_as_plan: "PRO",
            api_call_limits: %{"minute" => 100, "hour" => 1000, "month" => 10_000},
            metric_access: %{
              "accessible" => [],
              "accessible_patterns" => ["[invalid"],
              "not_accessible" => [],
              "not_accessible_patterns" => []
            },
            query_access: %{
              "accessible" => "all",
              "not_accessible" => [],
              "not_accessible_patterns" => []
            },
            signal_access: %{
              "accessible" => "all",
              "not_accessible" => [],
              "not_accessible_patterns" => []
            }
          },
          amount: 10_000,
          currency: "USD",
          interval: "month"
        })

      assert {:error, %Ecto.Changeset{}} = result
    end

    test "rejects non-list accessible_patterns", context do
      Sanbase.Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 9201")

      result =
        Sanbase.Billing.Plan.create_custom_api_plan(%{
          id: 9200,
          name: "CUSTOM_NONLIST",
          product_id: context.product_api.id,
          stripe_id: context.product_api.stripe_id,
          restrictions: %{
            restricted_access_as_plan: "PRO",
            api_call_limits: %{"minute" => 100, "hour" => 1000, "month" => 10_000},
            metric_access: %{
              "accessible" => "all",
              "accessible_patterns" => "social_.*",
              "not_accessible" => [],
              "not_accessible_patterns" => []
            },
            query_access: %{
              "accessible" => "all",
              "not_accessible" => [],
              "not_accessible_patterns" => []
            },
            signal_access: %{
              "accessible" => "all",
              "not_accessible" => [],
              "not_accessible_patterns" => []
            }
          },
          amount: 10_000,
          currency: "USD",
          interval: "month"
        })

      assert {:error, %Ecto.Changeset{}} = result
    end

    test "accepts valid regex patterns", context do
      Sanbase.Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 9301")

      result =
        Sanbase.Billing.Plan.create_custom_api_plan(%{
          id: 9300,
          name: "CUSTOM_GOOD_REGEX",
          product_id: context.product_api.id,
          stripe_id: context.product_api.stripe_id,
          restrictions: %{
            restricted_access_as_plan: "PRO",
            api_call_limits: %{"minute" => 100, "hour" => 1000, "month" => 10_000},
            metric_access: %{
              "accessible" => [],
              "accessible_patterns" => ["^social_.*", "sentiment_.*", "_usd$"],
              "not_accessible" => [],
              "not_accessible_patterns" => ["social_dominance_.*"]
            },
            query_access: %{
              "accessible" => "all",
              "not_accessible" => [],
              "not_accessible_patterns" => []
            },
            signal_access: %{
              "accessible" => "all",
              "not_accessible" => [],
              "not_accessible_patterns" => []
            }
          },
          amount: 10_000,
          currency: "USD",
          interval: "month"
        })

      assert {:ok, %Sanbase.Billing.Plan{}} = result
    end
  end

  describe "accessible_patterns" do
    setup context do
      Sanbase.Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 2001")

      {:ok, plan} =
        create_custom_api_plan_with_accessible_patterns(context)

      product_code = Sanbase.Billing.Product.code_by_id(plan.product_id)

      on_exit(fn ->
        :persistent_term.erase({Sanbase.Billing.Plan.CustomPlan.Loader, plan.name, product_code})
      end)

      user = insert(:user, metric_access_level: "alpha")
      _sub = insert(:subscription, user: user, plan_id: plan.id)
      {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)
      conn = setup_apikey_auth(build_conn(), apikey)

      %{pattern_plan: plan, pattern_conn: conn, pattern_user: user}
    end

    test "accessible_patterns expands to matching metrics from all available", context do
      %{pattern_plan: plan} = context

      %{resolved_metrics: resolved_metrics} =
        Sanbase.Billing.Plan.CustomPlan.Loader.get_data(
          plan.name,
          Sanbase.Billing.Product.code_by_id(plan.product_id)
        )

      all_metrics = Sanbase.Metric.free_metrics() ++ Sanbase.Metric.restricted_metrics()

      # Only social_* and sentiment_* metrics should be accessible,
      # minus the ones in the not_accessible list
      expected_social =
        Enum.filter(all_metrics, fn m ->
          String.match?(m, ~r/social_.*/) or String.match?(m, ~r/sentiment_.*/)
        end)
        |> Enum.reject(fn m -> m == "social_active_users" end)

      assert length(resolved_metrics) > 0
      assert Enum.sort(resolved_metrics) == Enum.sort(expected_social)

      # Non-social metrics should NOT be accessible
      assert "price_usd" not in resolved_metrics
      assert "daily_active_addresses" not in resolved_metrics
      assert "nvt" not in resolved_metrics
    end

    test "not_accessible has higher priority than accessible_patterns", context do
      %{pattern_plan: plan} = context

      %{resolved_metrics: resolved_metrics} =
        Sanbase.Billing.Plan.CustomPlan.Loader.get_data(
          plan.name,
          Sanbase.Billing.Product.code_by_id(plan.product_id)
        )

      # social_active_users is in the not_accessible list, so it should be excluded
      # even though it matches the "social_.*" pattern
      assert "social_active_users" not in resolved_metrics

      # But other social metrics should still be accessible
      assert "social_volume_total" in resolved_metrics
    end

    test "accessible_patterns combined with explicit accessible list", context do
      Sanbase.Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 3001")

      {:ok, plan} =
        create_custom_api_plan_with_combined_accessible(context)

      %{resolved_metrics: resolved_metrics} =
        Sanbase.Billing.Plan.CustomPlan.Loader.get_data(
          plan.name,
          Sanbase.Billing.Product.code_by_id(plan.product_id)
        )

      # price_usd is in the explicit accessible list
      assert "price_usd" in resolved_metrics

      # social metrics come from the accessible_patterns
      assert "social_volume_total" in resolved_metrics

      # Other metrics not in the list or pattern should NOT be accessible
      assert "nvt" not in resolved_metrics
    end

    test "not_accessible_patterns has higher priority than accessible_patterns", context do
      Sanbase.Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 4001")

      {:ok, plan} =
        create_custom_api_plan_with_conflicting_patterns(context)

      %{resolved_metrics: resolved_metrics} =
        Sanbase.Billing.Plan.CustomPlan.Loader.get_data(
          plan.name,
          Sanbase.Billing.Product.code_by_id(plan.product_id)
        )

      all_metrics = Sanbase.Metric.free_metrics() ++ Sanbase.Metric.restricted_metrics()

      # social_* metrics should be accessible (from accessible_patterns)
      social_metrics =
        Enum.filter(all_metrics, fn m -> String.match?(m, ~r/social_.*/) end)

      # But social_dominance_.* should be excluded (from not_accessible_patterns)
      social_dominance_metrics =
        Enum.filter(all_metrics, fn m -> String.match?(m, ~r/social_dominance_.*/) end)

      for m <- social_dominance_metrics do
        assert m not in resolved_metrics
      end

      # Other social metrics (non-dominance) should still be accessible
      non_dominance_social = social_metrics -- social_dominance_metrics

      for m <- non_dominance_social do
        assert m in resolved_metrics
      end
    end

    test "plan with accessible_patterns blocks non-matching metrics via GraphQL", context do
      %{pattern_conn: conn} = context

      project = insert(:random_project)

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: []}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        # price_usd is NOT a social metric, should be blocked
        assert %{"errors" => [error]} = get_metric(conn, "price_usd")

        assert error["message"] =~
                 "metric price_usd is not included"

        # social_volume_total IS a social metric, should be allowed
        result =
          get_metric(conn, "social_volume_total",
            slug: project.slug,
            from: "utc_now-300d",
            to: "utc_now"
          )

        assert result == %{"data" => %{"getMetric" => %{"timeseriesData" => []}}}
      end)
    end

    test "accessible_patterns with ^ anchor matches only metrics starting with the pattern",
         context do
      Sanbase.Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 5001")

      {:ok, plan} =
        create_custom_api_plan_with_start_anchor(context)

      %{resolved_metrics: resolved_metrics} =
        Sanbase.Billing.Plan.CustomPlan.Loader.get_data(
          plan.name,
          Sanbase.Billing.Product.code_by_id(plan.product_id)
        )

      all_metrics = Sanbase.Metric.free_metrics() ++ Sanbase.Metric.restricted_metrics()

      # Only metrics starting with "price" should be accessible
      expected = Enum.filter(all_metrics, fn m -> String.starts_with?(m, "price") end)
      assert length(resolved_metrics) > 0
      assert Enum.sort(resolved_metrics) == Enum.sort(expected)

      # "price_usd" starts with "price" -> accessible
      assert "price_usd" in resolved_metrics

      # "adjusted_price_daa_divergence" contains "price" but does NOT start with it -> not accessible
      assert "adjusted_price_daa_divergence" not in resolved_metrics
    end

    test "accessible_patterns with $ anchor matches only metrics ending with the pattern",
         context do
      Sanbase.Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 6001")

      {:ok, plan} =
        create_custom_api_plan_with_end_anchor(context)

      %{resolved_metrics: resolved_metrics} =
        Sanbase.Billing.Plan.CustomPlan.Loader.get_data(
          plan.name,
          Sanbase.Billing.Product.code_by_id(plan.product_id)
        )

      all_metrics = Sanbase.Metric.free_metrics() ++ Sanbase.Metric.restricted_metrics()

      # Only metrics ending with "_usd" should be accessible
      expected = Enum.filter(all_metrics, fn m -> String.ends_with?(m, "_usd") end)
      assert length(resolved_metrics) > 0
      assert Enum.sort(resolved_metrics) == Enum.sort(expected)

      # "price_usd" ends with "_usd" -> accessible
      assert "price_usd" in resolved_metrics
      # "price_btc" does NOT end with "_usd" -> not accessible
      assert "price_btc" not in resolved_metrics
    end

    test "not_accessible set to 'all' results in no accessible metrics", context do
      Sanbase.Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 7001")

      {:ok, plan} =
        create_custom_api_plan_with_not_accessible_all(context)

      %{resolved_metrics: resolved_metrics} =
        Sanbase.Billing.Plan.CustomPlan.Loader.get_data(
          plan.name,
          Sanbase.Billing.Product.code_by_id(plan.product_id)
        )

      assert resolved_metrics == []
    end

    test "not_accessible 'all' has higher priority than accessible_patterns", context do
      Sanbase.Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 8001")

      {:ok, plan} =
        create_custom_api_plan_with_patterns_and_not_accessible_all(context)

      %{resolved_metrics: resolved_metrics} =
        Sanbase.Billing.Plan.CustomPlan.Loader.get_data(
          plan.name,
          Sanbase.Billing.Product.code_by_id(plan.product_id)
        )

      # accessible_patterns would include social metrics, but not_accessible: "all" removes everything
      assert resolved_metrics == []
    end

    test "backward compatibility - missing accessible_patterns defaults to empty", context do
      # The existing plan from the main setup has no accessible_patterns key
      %{plan: plan} = context

      %{resolved_metrics: resolved_metrics} =
        Sanbase.Billing.Plan.CustomPlan.Loader.get_data(
          plan.name,
          Sanbase.Billing.Product.code_by_id(plan.product_id)
        )

      # Should still work as before - all metrics except explicitly excluded ones
      assert "price_usd" in resolved_metrics
      assert "social_volume_total" in resolved_metrics
      assert "daily_active_addresses" not in resolved_metrics
    end
  end

  defp create_custom_api_plan(context) do
    restrictions_args = %{
      name: "CUSTOM_PLAN_FOR_TEST",
      restricted_access_as_plan: "PRO",
      requested_product: "SANAPI",
      api_call_limits: %{"minute" => 1000, "hour" => 100_000, "month" => 3_000_000},
      historical_data_in_days: 365,
      realtime_data_cut_off_in_days: 0,
      metric_access: %{
        "accessible" => "all",
        "not_accessible" => ["daily_active_addresses"],
        "not_accessible_patterns" => ["mvrv_usd"]
      },
      query_access: %{
        "accessible" => "all",
        "not_accessible" => ["history_price"],
        "not_accessible_patterns" => ["mvrv"]
      },
      signal_access: %{
        "accessible" => "all",
        "not_accessible" => [],
        "not_accessible_patterns" => []
      }
    }

    {:ok, plan} =
      Sanbase.Billing.Plan.create_custom_api_plan(%{
        id: 1000,
        name: "CUSTOM_API_PLAN",
        product_id: context.product_api.id,
        stripe_id: context.product_api.stripe_id,
        restrictions: restrictions_args,
        amount: 35_900,
        currency: "USD",
        interval: "month"
      })

    {:ok, plan}
  end

  # Plan that uses accessible_patterns to allow ONLY social/sentiment metrics
  defp create_custom_api_plan_with_accessible_patterns(context) do
    restrictions_args = %{
      name: "CUSTOM_SOCIAL_ONLY_PLAN",
      restricted_access_as_plan: "PRO",
      requested_product: "SANAPI",
      api_call_limits: %{"minute" => 1000, "hour" => 100_000, "month" => 3_000_000},
      historical_data_in_days: 365,
      realtime_data_cut_off_in_days: 0,
      metric_access: %{
        "accessible" => [],
        "accessible_patterns" => ["social_.*", "sentiment_.*"],
        "not_accessible" => ["social_active_users"],
        "not_accessible_patterns" => []
      },
      query_access: %{
        "accessible" => "all",
        "not_accessible" => [],
        "not_accessible_patterns" => []
      },
      signal_access: %{
        "accessible" => "all",
        "not_accessible" => [],
        "not_accessible_patterns" => []
      }
    }

    Sanbase.Billing.Plan.create_custom_api_plan(%{
      id: 2000,
      name: "CUSTOM_SOCIAL_ONLY",
      product_id: context.product_api.id,
      stripe_id: context.product_api.stripe_id,
      restrictions: restrictions_args,
      amount: 19_900,
      currency: "USD",
      interval: "month"
    })
  end

  # Plan that combines explicit accessible list with accessible_patterns
  defp create_custom_api_plan_with_combined_accessible(context) do
    restrictions_args = %{
      name: "CUSTOM_COMBINED_PLAN",
      restricted_access_as_plan: "PRO",
      requested_product: "SANAPI",
      api_call_limits: %{"minute" => 1000, "hour" => 100_000, "month" => 3_000_000},
      historical_data_in_days: 365,
      realtime_data_cut_off_in_days: 0,
      metric_access: %{
        "accessible" => ["price_usd"],
        "accessible_patterns" => ["social_.*"],
        "not_accessible" => [],
        "not_accessible_patterns" => []
      },
      query_access: %{
        "accessible" => "all",
        "not_accessible" => [],
        "not_accessible_patterns" => []
      },
      signal_access: %{
        "accessible" => "all",
        "not_accessible" => [],
        "not_accessible_patterns" => []
      }
    }

    Sanbase.Billing.Plan.create_custom_api_plan(%{
      id: 3000,
      name: "CUSTOM_COMBINED",
      product_id: context.product_api.id,
      stripe_id: context.product_api.stripe_id,
      restrictions: restrictions_args,
      amount: 29_900,
      currency: "USD",
      interval: "month"
    })
  end

  # Plan where accessible_patterns and not_accessible_patterns conflict
  defp create_custom_api_plan_with_conflicting_patterns(context) do
    restrictions_args = %{
      name: "CUSTOM_CONFLICT_PLAN",
      restricted_access_as_plan: "PRO",
      requested_product: "SANAPI",
      api_call_limits: %{"minute" => 1000, "hour" => 100_000, "month" => 3_000_000},
      historical_data_in_days: 365,
      realtime_data_cut_off_in_days: 0,
      metric_access: %{
        "accessible" => [],
        "accessible_patterns" => ["social_.*"],
        "not_accessible" => [],
        "not_accessible_patterns" => ["social_dominance_.*"]
      },
      query_access: %{
        "accessible" => "all",
        "not_accessible" => [],
        "not_accessible_patterns" => []
      },
      signal_access: %{
        "accessible" => "all",
        "not_accessible" => [],
        "not_accessible_patterns" => []
      }
    }

    Sanbase.Billing.Plan.create_custom_api_plan(%{
      id: 4000,
      name: "CUSTOM_CONFLICT",
      product_id: context.product_api.id,
      stripe_id: context.product_api.stripe_id,
      restrictions: restrictions_args,
      amount: 29_900,
      currency: "USD",
      interval: "month"
    })
  end

  # Plan with ^ anchor - only metrics starting with "price"
  defp create_custom_api_plan_with_start_anchor(context) do
    restrictions_args = %{
      name: "CUSTOM_START_ANCHOR_PLAN",
      restricted_access_as_plan: "PRO",
      requested_product: "SANAPI",
      api_call_limits: %{"minute" => 1000, "hour" => 100_000, "month" => 3_000_000},
      historical_data_in_days: 365,
      realtime_data_cut_off_in_days: 0,
      metric_access: %{
        "accessible" => [],
        "accessible_patterns" => ["^price"],
        "not_accessible" => [],
        "not_accessible_patterns" => []
      },
      query_access: %{
        "accessible" => "all",
        "not_accessible" => [],
        "not_accessible_patterns" => []
      },
      signal_access: %{
        "accessible" => "all",
        "not_accessible" => [],
        "not_accessible_patterns" => []
      }
    }

    Sanbase.Billing.Plan.create_custom_api_plan(%{
      id: 5000,
      name: "CUSTOM_START_ANCHOR",
      product_id: context.product_api.id,
      stripe_id: context.product_api.stripe_id,
      restrictions: restrictions_args,
      amount: 19_900,
      currency: "USD",
      interval: "month"
    })
  end

  # Plan with $ anchor - only metrics ending with "_usd"
  defp create_custom_api_plan_with_end_anchor(context) do
    restrictions_args = %{
      name: "CUSTOM_END_ANCHOR_PLAN",
      restricted_access_as_plan: "PRO",
      requested_product: "SANAPI",
      api_call_limits: %{"minute" => 1000, "hour" => 100_000, "month" => 3_000_000},
      historical_data_in_days: 365,
      realtime_data_cut_off_in_days: 0,
      metric_access: %{
        "accessible" => [],
        "accessible_patterns" => ["_usd$"],
        "not_accessible" => [],
        "not_accessible_patterns" => []
      },
      query_access: %{
        "accessible" => "all",
        "not_accessible" => [],
        "not_accessible_patterns" => []
      },
      signal_access: %{
        "accessible" => "all",
        "not_accessible" => [],
        "not_accessible_patterns" => []
      }
    }

    Sanbase.Billing.Plan.create_custom_api_plan(%{
      id: 6000,
      name: "CUSTOM_END_ANCHOR",
      product_id: context.product_api.id,
      stripe_id: context.product_api.stripe_id,
      restrictions: restrictions_args,
      amount: 19_900,
      currency: "USD",
      interval: "month"
    })
  end

  # Plan with not_accessible: "all" - nothing should be accessible
  defp create_custom_api_plan_with_not_accessible_all(context) do
    Sanbase.Billing.Plan.create_custom_api_plan(%{
      id: 7000,
      name: "CUSTOM_NOT_ACCESSIBLE_ALL",
      product_id: context.product_api.id,
      stripe_id: context.product_api.stripe_id,
      restrictions: %{
        restricted_access_as_plan: "PRO",
        api_call_limits: %{"minute" => 1000, "hour" => 100_000, "month" => 3_000_000},
        historical_data_in_days: 365,
        realtime_data_cut_off_in_days: 0,
        metric_access: %{
          "accessible" => "all",
          "not_accessible" => "all",
          "not_accessible_patterns" => []
        },
        query_access: %{
          "accessible" => "all",
          "not_accessible" => [],
          "not_accessible_patterns" => []
        },
        signal_access: %{
          "accessible" => "all",
          "not_accessible" => [],
          "not_accessible_patterns" => []
        }
      },
      amount: 19_900,
      currency: "USD",
      interval: "month"
    })
  end

  # Plan with accessible_patterns + not_accessible: "all" - nothing accessible
  defp create_custom_api_plan_with_patterns_and_not_accessible_all(context) do
    Sanbase.Billing.Plan.create_custom_api_plan(%{
      id: 8000,
      name: "CUSTOM_PATTERNS_AND_NOT_ALL",
      product_id: context.product_api.id,
      stripe_id: context.product_api.stripe_id,
      restrictions: %{
        restricted_access_as_plan: "PRO",
        api_call_limits: %{"minute" => 1000, "hour" => 100_000, "month" => 3_000_000},
        historical_data_in_days: 365,
        realtime_data_cut_off_in_days: 0,
        metric_access: %{
          "accessible" => [],
          "accessible_patterns" => ["social_.*", "sentiment_.*"],
          "not_accessible" => "all",
          "not_accessible_patterns" => []
        },
        query_access: %{
          "accessible" => "all",
          "not_accessible" => [],
          "not_accessible_patterns" => []
        },
        signal_access: %{
          "accessible" => "all",
          "not_accessible" => [],
          "not_accessible_patterns" => []
        }
      },
      amount: 19_900,
      currency: "USD",
      interval: "month"
    })
  end

  defp get_metric(conn, metric, opts \\ []) do
    slug = Keyword.get(opts, :slug, "bitcoin")
    from = Keyword.get(opts, :from, "utc_now-1d")
    to = Keyword.get(opts, :to, "utc_now")

    query =
      ~s|{ getMetric(metric: "#{metric}"){ timeseriesData(from: "#{from}", to: "#{to}", slug: "#{slug}") {value} } }|

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp get_current_user(conn) do
    conn
    |> post("/graphql", query_skeleton("{ currentUser{ id } }"))
    |> json_response(200)
  end

  defp get_history_price(conn) do
    query =
      ~s|{ historyPrice(slug: "bitcoin" from: "utc_now-1d" to: "utc_now" interval: "5m"){ priceUsd } }|

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
