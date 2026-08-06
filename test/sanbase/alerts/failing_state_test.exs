defmodule Sanbase.Alert.Trigger.FailingStateTest do
  use ExUnit.Case, async: true

  alias Sanbase.Alert.Trigger
  alias Sanbase.Alert.Trigger.FailingState

  describe "permanent_failure?/1 - disables the alert on the spot" do
    test "invalid webhook URL is permanent" do
      assert FailingState.permanent_failure?({:error, %{reason: :webhook_url_not_valid}})
    end

    test "unreachable telegram chats are permanent" do
      assert FailingState.permanent_failure?({:error, %{reason: :telegram_chat_not_found}})
      assert FailingState.permanent_failure?({:error, %{reason: :telegram_bot_blocked}})
    end

    test "telegram 404 is not permanent - it means an invalid bot token, which is on us" do
      refute FailingState.permanent_failure?({:error, %{reason: :telegram_chat_not_found_404}})
    end

    test "webhook send failures are not permanent - they take the 7-day path" do
      refute FailingState.permanent_failure?({:error, %{reason: :webhook_send_fail}})
    end

    test "email failures and rate limits are not permanent" do
      refute FailingState.permanent_failure?({:error, %{reason: :email_send_fail}})
      refute FailingState.permanent_failure?({:error, "Too Many Requests: retry after 5"})
    end
  end

  describe "delivery_failure?/1 - counts towards the 7-day streak" do
    test "webhook send failures count" do
      assert FailingState.delivery_failure?({:error, %{reason: :webhook_send_fail}})
    end

    test "permanent failures do not count - they disable on the spot instead" do
      refute FailingState.delivery_failure?({:error, %{reason: :webhook_url_not_valid}})
      refute FailingState.delivery_failure?({:error, %{reason: :telegram_bot_blocked}})
    end

    test "email failures do not count - they can be on our provider's side" do
      refute FailingState.delivery_failure?({:error, %{reason: :email_send_fail}})
    end

    test "telegram rate limits and other raw errors do not count" do
      refute FailingState.delivery_failure?({:error, "Too Many Requests: retry after 5"})
    end

    test "daily alerts limit does not count" do
      refute FailingState.delivery_failure?({:error, %{reason: :alerts_limit_reached}})
    end

    test "successful sends do not count" do
      refute FailingState.delivery_failure?(:ok)
    end
  end

  describe "deactivate_now?/1" do
    test "disables immediately when all sends failed permanently" do
      assert FailingState.deactivate_now?(%{all_permanent_failures?: true})
    end

    test "keeps the alert when any channel delivered or failed transiently" do
      refute FailingState.deactivate_now?(%{all_permanent_failures?: false})
    end
  end

  describe "next/2" do
    test "a success clears the state" do
      trigger = %Trigger{
        failing_since: ~U[2026-08-01 00:00:00Z],
        failed_attempts: 10,
        consecutive_failed_days: 5,
        last_failed_on: ~D[2026-08-05]
      }

      assert FailingState.next(trigger, %{any_success?: true}) == %{
               failing_since: nil,
               failed_attempts: 0,
               consecutive_failed_days: 0,
               last_failed_on: nil
             }
    end

    test "first failure starts the state" do
      state =
        FailingState.next(%Trigger{}, %{
          any_success?: false,
          any_delivery_failure?: true,
          delivery_failures_count: 2
        })

      assert %DateTime{} = state.failing_since
      assert state.failed_attempts == 2
      assert state.consecutive_failed_days == 1
      assert state.last_failed_on == Date.utc_today()
    end

    test "failure on the next day extends the day chain" do
      trigger = %Trigger{
        failing_since: ~U[2026-08-01 00:00:00Z],
        failed_attempts: 5,
        consecutive_failed_days: 3,
        last_failed_on: Date.add(Date.utc_today(), -1)
      }

      state =
        FailingState.next(trigger, %{
          any_success?: false,
          any_delivery_failure?: true,
          delivery_failures_count: 1
        })

      assert state.consecutive_failed_days == 4
      assert state.failed_attempts == 6
      assert state.failing_since == trigger.failing_since
    end

    test "repeated failures within the same day do not extend the day chain" do
      trigger = %Trigger{
        failing_since: ~U[2026-08-01 00:00:00Z],
        failed_attempts: 5,
        consecutive_failed_days: 3,
        last_failed_on: Date.utc_today()
      }

      state =
        FailingState.next(trigger, %{
          any_success?: false,
          any_delivery_failure?: true,
          delivery_failures_count: 1
        })

      assert state.consecutive_failed_days == 3
      assert state.failed_attempts == 6
    end

    test "a day without failures restarts the day chain" do
      trigger = %Trigger{
        failing_since: ~U[2026-08-01 00:00:00Z],
        failed_attempts: 5,
        consecutive_failed_days: 6,
        last_failed_on: Date.add(Date.utc_today(), -3)
      }

      state =
        FailingState.next(trigger, %{
          any_success?: false,
          any_delivery_failure?: true,
          delivery_failures_count: 1
        })

      assert state.consecutive_failed_days == 1
      assert state.failing_since == trigger.failing_since
    end

    test "a round with neither success nor delivery failure keeps the state" do
      trigger = %Trigger{
        failing_since: ~U[2026-08-01 00:00:00Z],
        failed_attempts: 5,
        consecutive_failed_days: 3,
        last_failed_on: ~D[2026-08-05]
      }

      assert FailingState.next(trigger, %{any_success?: false, any_delivery_failure?: false}) ==
               %{
                 failing_since: trigger.failing_since,
                 failed_attempts: 5,
                 consecutive_failed_days: 3,
                 last_failed_on: trigger.last_failed_on
               }
    end
  end

  describe "deactivate?/1" do
    test "deactivates at 7 consecutive failed days" do
      refute FailingState.deactivate?(%{consecutive_failed_days: 6})
      assert FailingState.deactivate?(%{consecutive_failed_days: 7})
      assert FailingState.deactivate?(%{consecutive_failed_days: 8})
    end
  end
end
