defmodule Sanbase.Signal.TriggerPriceAbsoluteChangeTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import ExUnit.CaptureLog

  alias Sanbase.Signal.{UserTrigger, Evaluator}
  alias Sanbase.Signal.Trigger.PriceAbsoluteChangeSettings

  setup do
    Sanbase.Signal.Evaluator.Cache.clear()

    Tesla.Mock.mock(fn %{method: :post} -> %Tesla.Env{status: 200, body: "ok"} end)

    user = insert(:user)
    Sanbase.Auth.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    [
      project: insert(:random_erc20_project),
      price_usd: 62,
      user: user
    ]
  end

  describe "price absolute change" do
    test "only some of price absolute change signals triggered", context do
      %{user: user, project: project, price_usd: price_usd} = context
      # should trigger
      trigger_settings1 = price_absolute_change_settings(project, %{operation: %{above: 60}})
      trigger_settings2 = price_absolute_change_settings(project, %{operation: %{above: 70}})

      {:ok, trigger1} = create_trigger(user, trigger_settings1)
      {:ok, _} = create_trigger(user, trigger_settings2)

      Sanbase.Mock.prepare_mock2(
        &Sanbase.Price.aggregated_metric_timeseries_data/5,
        {:ok, %{project.slug => price_usd}}
      )
      |> Sanbase.Mock.prepare_mock2(&Sanbase.Chart.build_embedded_chart/4, [
        %{image: %{url: "url"}}
      ])
      |> Sanbase.Mock.run_with_mocks(fn ->
        [triggered | rest] =
          PriceAbsoluteChangeSettings.type()
          |> UserTrigger.get_active_triggers_by_type()
          |> Evaluator.run()

        assert rest == []
        assert trigger1.id == triggered.id
      end)
    end

    test "all operations trigger signal", context do
      %{user: user, project: project, price_usd: price_usd} = context

      trigger_settings1 = price_absolute_change_settings(project, %{operation: %{below: 80}})

      trigger_settings2 =
        price_absolute_change_settings(project, %{operation: %{inside_channel: [59, 65]}})

      trigger_settings3 =
        price_absolute_change_settings(project, %{operation: %{outside_channel: [80, 90]}})

      {:ok, _} = create_trigger(user, trigger_settings1)
      {:ok, _} = create_trigger(user, trigger_settings2)
      {:ok, _} = create_trigger(user, trigger_settings3)

      Sanbase.Mock.prepare_mock2(
        &Sanbase.Price.aggregated_metric_timeseries_data/5,
        {:ok, %{project.slug => price_usd}}
      )
      |> Sanbase.Mock.prepare_mock2(&Sanbase.Chart.build_embedded_chart/4, [
        %{image: %{url: "url"}}
      ])
      |> Sanbase.Mock.run_with_mocks(fn ->
        triggered =
          PriceAbsoluteChangeSettings.type()
          |> UserTrigger.get_active_triggers_by_type()
          |> Evaluator.run()

        assert length(triggered) == 3

        payload_list =
          triggered |> Enum.map(fn ut -> ut.trigger.settings.payload[project.slug] end)

        expected_payload = [
          "**#{project.name}**'s price has reached below $80 and is now $62.0",
          "**#{project.name}**'s price has reached between $59 and $65 and is now $62.0",
          "**#{project.name}**'s price has reached below $80 or above >= $90 and is now $62.0"
        ]

        all_expectd_payload_present? =
          Enum.all?(expected_payload, fn expected ->
            Enum.any?(payload_list, fn payload -> String.contains?(payload, expected) end)
          end)

        assert all_expectd_payload_present?
      end)
    end

    test "none of these operations trigger signal", context do
      %{user: user, project: project, price_usd: price_usd} = context

      trigger_settings1 = price_absolute_change_settings(project, %{operation: %{below: 50}})

      trigger_settings2 =
        price_absolute_change_settings(project, %{operation: %{inside_channel: [40, 50]}})

      trigger_settings3 =
        price_absolute_change_settings(project, %{operation: %{outside_channel: [30, 90]}})

      {:ok, _} = create_trigger(user, trigger_settings1)
      {:ok, _} = create_trigger(user, trigger_settings2)
      {:ok, _} = create_trigger(user, trigger_settings3)

      Sanbase.Mock.prepare_mock2(
        &Sanbase.Price.aggregated_metric_timeseries_data/5,
        {:ok, %{project.slug => price_usd}}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        triggered =
          PriceAbsoluteChangeSettings.type()
          |> UserTrigger.get_active_triggers_by_type()
          |> Evaluator.run()

        assert triggered == []
      end)
    end

    test "signal setting cooldown works", context do
      %{user: user, project: project, price_usd: price_usd} = context

      trigger_settings1 = price_absolute_change_settings(project, %{operation: %{above: 60}})
      trigger_settings2 = price_absolute_change_settings(project, %{operation: %{above: 70}})

      create_trigger(user, trigger_settings1)
      create_trigger(user, trigger_settings2)

      Tesla.Mock.mock_global(fn
        %{method: :post} ->
          %Tesla.Env{status: 200, body: "ok"}
      end)

      Sanbase.Mock.prepare_mock2(
        &Sanbase.Price.aggregated_metric_timeseries_data/5,
        {:ok, %{project.slug => price_usd}}
      )
      |> Sanbase.Mock.prepare_mock2(&Sanbase.Chart.build_embedded_chart/4, [
        %{image: %{url: "url"}}
      ])
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert capture_log(fn ->
                 Sanbase.Signal.Scheduler.run_signal(PriceAbsoluteChangeSettings)
               end) =~ "In total 1/1 price_absolute_change signals were sent successfully"

        Sanbase.Signal.Evaluator.Cache.clear()

        assert capture_log(fn ->
                 Sanbase.Signal.Scheduler.run_signal(PriceAbsoluteChangeSettings)
               end) =~ "There were no signals triggered of type"
      end)
    end
  end

  defp create_trigger(user, settings) do
    UserTrigger.create_user_trigger(user, %{
      title: "Generic title",
      is_public: true,
      cooldown: "12h",
      settings: settings
    })
  end

  defp price_absolute_change_settings(project, price_opts) do
    Map.merge(
      %{type: "price_absolute_change", target: %{slug: project.slug}, channel: "telegram"},
      price_opts
    )
  end
end
