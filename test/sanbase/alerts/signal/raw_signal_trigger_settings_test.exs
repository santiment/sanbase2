defmodule Sanbase.Alert.RawSignalTriggerSettingsTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers

  alias Sanbase.Alert.UserTrigger
  alias Sanbase.Alert.Evaluator
  alias Sanbase.Alert.Trigger.RawSignalTriggerSettings

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

    test "when there is signal for target, fire an alert", context do
      %{project: project, user: user} = context

      settings = %{
        type: RawSignalTriggerSettings.type(),
        signal: "mvrv_usd_30d_lower_zone",
        target: %{slug: [project.slug]},
        channel: "telegram"
      }

      raw_data_result = {:ok, [%{slug: project.slug}]}

      {:ok, trigger} = create_user_trigger(user, settings)

      Sanbase.Mock.prepare_mock2(&Sanbase.Signal.raw_data/4, raw_data_result)
      |> Sanbase.Mock.run_with_mocks(fn ->
        [triggered] =
          RawSignalTriggerSettings.type()
          |> UserTrigger.get_active_triggers_by_type()
          |> Evaluator.run()

        assert triggered.id == trigger.id
      end)
    end

    test "when there is no signal for target, don't fire an alert", context do
      %{user: user, project: project} = context
      other_project = Sanbase.Factory.insert(:random_project)

      settings = %{
        type: RawSignalTriggerSettings.type(),
        signal: "mvrv_usd_30d_lower_zone",
        target: %{slug: project.slug},
        channel: "telegram"
      }

      raw_data_result = {:ok, [%{slug: other_project.slug}]}

      {:ok, trigger} = create_user_trigger(user, settings)

      Sanbase.Mock.prepare_mock2(&Sanbase.Signal.raw_data/4, raw_data_result)
      |> Sanbase.Mock.run_with_mocks(fn ->
        triggered =
          RawSignalTriggerSettings.type()
          |> UserTrigger.get_active_triggers_by_type()
          |> Evaluator.run()

        assert triggered == []
      end)
    end
  end

  def create_user_trigger(user, settings) do
    UserTrigger.create_user_trigger(user, %{
      title: "Generic title",
      is_public: true,
      cooldown: "12h",
      settings: settings
    })
  end
end
