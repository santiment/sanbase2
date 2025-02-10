defmodule Sanbase.Alert.TriggerRestrictionsTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Billing.Plan.SanbaseAccessChecker

  setup do
    trigger_settings = %{
      type: "metric_signal",
      metric: "active_addresses_24h",
      target: %{slug: "santiment"},
      channel: "telegram",
      time_window: "1d",
      operation: %{percent_up: 300.0}
    }

    %{trigger_settings: trigger_settings}
  end

  defp create_trigger(conn) do
    trigger_settings = %{
      type: "metric_signal",
      metric: "active_addresses_24h",
      target: %{slug: "santiment"},
      channel: "telegram",
      time_window: "1d",
      operation: %{percent_up: 200.0}
    }

    mutation =
      ~s"""
      mutation {
        createTrigger(
          settings: '#{Jason.encode!(trigger_settings)}'
          title: 'Generic title'
          cooldown: '23h'
        ) {
          trigger{
            id
            cooldown
            settings
          }
        }
      }
      """
      |> String.replace(~r|\"|, ~S|\\"|)
      |> String.replace(~r|'|, ~S|"|)

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  test "sanbase free user has a limit of 3 alerts" do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    assert SanbaseAccessChecker.alerts_limit("FREE") == 3

    for _ <- 1..3 do
      assert %{"data" => %{"createTrigger" => _}} = create_trigger(conn)
    end

    error_msg = conn |> create_trigger() |> get_in(["errors", Access.at(0), "message"])

    assert error_msg =~
             "You have reached the limit of alerts for your plan (3).Please upgrade your plan to create more alerts."
  end

  test "sanbase pro user has a limit of 20 alerts" do
    user = insert(:user)
    _ = insert(:subscription_pro_sanbase, user: user)
    conn = setup_jwt_auth(build_conn(), user)

    assert SanbaseAccessChecker.alerts_limit("PRO") == 20

    for _ <- 1..20 do
      assert %{"data" => %{"createTrigger" => _}} = create_trigger(conn)
    end

    error_msg = conn |> create_trigger() |> get_in(["errors", Access.at(0), "message"])

    assert error_msg =~
             "You have reached the limit of alerts for your plan (20).Please upgrade your plan to create more alerts."
  end

  test "sanbase pro+ user has no limits" do
    user = insert(:user)
    _ = insert(:subscription_pro_sanbase, user: user)
    conn = setup_jwt_auth(build_conn(), user)

    assert SanbaseAccessChecker.alerts_limit("PRO_PLUS") == 50

    for _ <- 1..49 do
      assert %{"data" => %{"createTrigger" => _}} = create_trigger(conn)
    end
  end
end
