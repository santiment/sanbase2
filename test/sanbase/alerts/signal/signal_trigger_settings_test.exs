defmodule Sanbase.Alert.SignalTriggerSettingsTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers
  import ExUnit.CaptureLog

  alias Sanbase.Alert.UserTrigger
  alias Sanbase.Alert.Evaluator
  alias Sanbase.Alert.Trigger.SignalTriggerSettings

  setup_all_with_mocks([
    {
      Sanbase.Timeline.TimelineEvent,
      [:passthrough],
      maybe_create_event_async: fn user_trigger_tuple, _, _ -> user_trigger_tuple end
    }
  ]) do
    []
  end

  describe "signal trigger settings" do
    setup do
      # Clean children on exit, otherwise DB calls from async tasks can be attempted
      clean_task_supervisor_children()

      Sanbase.Cache.clear_all(:alerts_evaluator_cache)

      user = insert(:user)
      Sanbase.Accounts.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

      project = Sanbase.Factory.insert(:random_project)

      %{user: user, project: project}
    end

    test "any signals", context do
      %{project: project, user: user} = context

      trigger_settings = %{
        type: "signal_data",
        signal: "dai_mint",
        target: %{slug: project.slug},
        channel: "telegram",
        operation: %{above: 0}
      }

      {:ok, trigger} =
        UserTrigger.create_user_trigger(user, %{
          title: "Generic title",
          is_public: true,
          cooldown: "12h",
          settings: trigger_settings
        })

      # Return a fun with arity 5 that will return different results
      # for consecutive calls
      mock_fun =
        [
          fn -> {:ok, %{project.slug => 1}} end,
          fn -> {:ok, %{project.slug => 5}} end
        ]
        |> Sanbase.Mock.wrap_consecutives(arity: 5)

      Sanbase.Mock.prepare_mock(
        Sanbase.Signal.SignalAdapter,
        :aggregated_timeseries_data,
        mock_fun
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        [triggered] =
          SignalTriggerSettings.type()
          |> UserTrigger.get_active_triggers_by_type()
          |> Evaluator.run()

        assert triggered.id == trigger.id
      end)
    end

    test "no signals", context do
      %{project: project, user: user} = context

      trigger_settings = %{
        type: "signal_data",
        signal: "dai_mint",
        target: %{slug: project.slug},
        channel: "telegram",
        operation: %{above: 0}
      }

      {:ok, _trigger} =
        UserTrigger.create_user_trigger(user, %{
          title: "Generic title",
          is_public: true,
          cooldown: "12h",
          settings: trigger_settings
        })

      # Return a fun with arity 5 that will return different results
      # for consecutive calls
      mock_fun =
        [
          fn -> {:ok, %{project.slug => 0}} end
        ]
        |> Sanbase.Mock.wrap_consecutives(arity: 5)

      Sanbase.Mock.prepare_mock(
        Sanbase.Signal.SignalAdapter,
        :aggregated_timeseries_data,
        mock_fun
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        triggered =
          SignalTriggerSettings.type()
          |> UserTrigger.get_active_triggers_by_type()
          |> Evaluator.run()

        assert triggered == []
      end)
    end

    test "cannot trigger for random signal", context do
      %{project: project, user: user} = context

      trigger_settings = %{
        type: "signal_data",
        signal: rand_str(),
        target: %{slug: project.slug},
        channel: "telegram",
        operation: %{above: 0}
      }

      assert capture_log(fn ->
               {:error, error_msg} =
                 UserTrigger.create_user_trigger(user, %{
                   title: "Generic title",
                   is_public: true,
                   cooldown: "12h",
                   settings: trigger_settings
                 })

               assert error_msg =~ "not supported, is deprecated or is mistyped"
             end)
    end
  end
end
