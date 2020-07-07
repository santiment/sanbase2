defmodule Sanbase.Signal.TriggerPricePercentChangeTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Signal.{Trigger, UserTrigger, Evaluator}
  alias Sanbase.Signal.Trigger.PricePercentChangeSettings

  setup do
    Sanbase.Signal.Evaluator.Cache.clear_all()

    Tesla.Mock.mock(fn %{method: :post} -> %Tesla.Env{status: 200, body: "ok"} end)

    user = insert(:user)
    Sanbase.Auth.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    project = insert(:random_erc20_project)

    [project: project, user: user]
  end

  test "moving up - only some triggered", context do
    %{user: user, project: project} = context

    trigger_settings1 = price_percent_change_settings(project, %{operation: %{percent_up: 18.0}})

    trigger_settings2 = price_percent_change_settings(project, %{operation: %{percent_up: 15.0}})

    {:ok, _} = create_trigger(user, trigger_settings1)
    {:ok, trigger2} = create_trigger(user, trigger_settings2)

    ohlc = %{
      open_price_usd: 53.512,
      close_price_usd: 62.12312,
      high_price_usd: 70.5121,
      low_price_usd: 40.12512
    }

    Sanbase.Mock.prepare_mock2(&Sanbase.Price.ohlc/3, {:ok, ohlc})
    |> Sanbase.Mock.run_with_mocks(fn ->
      [triggered | rest] =
        PricePercentChangeSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      assert rest == []
      assert trigger2.id == triggered.id
      assert Trigger.triggered?(triggered.trigger) == true

      payload = triggered.trigger.settings.payload |> Map.values() |> hd()

      assert payload =~ "price increased by 16.09%"
      assert payload =~ "now: $62.12"
    end)
  end

  test "moving down - only some triggered", context do
    %{user: user, project: project} = context

    # should trigger signal
    trigger_settings1 =
      price_percent_change_settings(project, %{operation: %{percent_down: 20.0}})

    trigger_settings2 = price_percent_change_settings(project, %{operation: %{percent_up: 40.0}})

    {:ok, trigger1} = create_trigger(user, trigger_settings1)
    {:ok, _} = create_trigger(user, trigger_settings2)

    ohlc = %{open_price_usd: 53, close_price_usd: 40, high_price_usd: 70, low_price_usd: 40}

    Sanbase.Mock.prepare_mock2(&Sanbase.Price.ohlc/3, {:ok, ohlc})
    |> Sanbase.Mock.run_with_mocks(fn ->
      [triggered | rest] =
        PricePercentChangeSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      assert rest == []
      assert trigger1.id == triggered.id
      assert Trigger.triggered?(triggered.trigger) == true
    end)
  end

  test "moving up or move down - percent_up triggered", context do
    %{user: user, project: project} = context

    trigger_settings =
      price_percent_change_settings(project, %{
        operation: %{some_of: [%{percent_up: 15}, %{percent_down: 100}]}
      })

    {:ok, trigger} = create_trigger(user, trigger_settings)

    ohlc = %{open_price_usd: 53, close_price_usd: 62, high_price_usd: 70, low_price_usd: 0.1}

    Sanbase.Mock.prepare_mock2(&Sanbase.Price.ohlc/3, {:ok, ohlc})
    |> Sanbase.Mock.run_with_mocks(fn ->
      [triggered | rest] =
        PricePercentChangeSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      assert rest == []
      assert Trigger.triggered?(triggered.trigger) == true
      assert triggered.id == trigger.id
    end)
  end

  test "moving up or move down - percent_down triggered", context do
    %{user: user, project: project} = context

    trigger_settings =
      price_percent_change_settings(project, %{
        operation: %{some_of: [%{percent_up: 1500}, %{percent_down: 20}]}
      })

    {:ok, trigger} = create_trigger(user, trigger_settings)

    ohlc = %{open_price_usd: 53, close_price_usd: 1, high_price_usd: 70, low_price_usd: 0.1}

    Sanbase.Mock.prepare_mock2(&Sanbase.Price.ohlc/3, {:ok, ohlc})
    |> Sanbase.Mock.run_with_mocks(fn ->
      [triggered | rest] =
        PricePercentChangeSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      assert rest == []
      assert Trigger.triggered?(triggered.trigger) == true
      assert triggered.id == trigger.id
    end)
  end

  test "move up and move down - nothing triggered", context do
    %{user: user, project: project} = context

    trigger_settings =
      price_percent_change_settings(project, %{
        operation: %{none_of: [%{percent_up: 0.001}, %{percent_down: 0.00001}]}
      })

    create_trigger(user, trigger_settings)

    ohlc = %{open_price_usd: 53, close_price_usd: 62, high_price_usd: 70, low_price_usd: 0.1}

    Sanbase.Mock.prepare_mock2(&Sanbase.Price.ohlc/3, {:ok, ohlc})
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert [] ==
               PricePercentChangeSettings.type()
               |> UserTrigger.get_active_triggers_by_type()
               |> Evaluator.run()
    end)
  end

  test "move up and move down - triggered", context do
    %{user: user, project: project} = context

    trigger_settings =
      price_percent_change_settings(project, %{
        operation: %{all_of: [%{percent_up: 15}, %{percent_up: 10}]}
      })

    {:ok, trigger} = create_trigger(user, trigger_settings)

    ohlc = %{open_price_usd: 53, close_price_usd: 62, high_price_usd: 70, low_price_usd: 0.1}

    Sanbase.Mock.prepare_mock2(&Sanbase.Price.ohlc/3, {:ok, ohlc})
    |> Sanbase.Mock.run_with_mocks(fn ->
      [triggered | rest] =
        PricePercentChangeSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      assert rest == []
      assert Trigger.triggered?(triggered.trigger) == true
      assert triggered.id == trigger.id
    end)
  end

  defp create_trigger(user, settings) do
    UserTrigger.create_user_trigger(user, %{
      title: "Generic title",
      is_public: true,
      cooldown: "12h",
      settings: settings
    })
  end

  defp price_percent_change_settings(project, price_opts) do
    Map.merge(
      %{
        type: "price_percent_change",
        target: %{slug: project.slug},
        channel: "telegram",
        time_window: "6h"
      },
      price_opts
    )
  end
end
