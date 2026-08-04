defmodule Sanbase.Logger.ActivityTracesFilterWatchdogTest do
  # async: false — mutates the BEAM-global `:logger` primary filter list.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Sanbase.Logger.ActivityTracesFilterWatchdog, as: Watchdog
  alias Sanbase.Logger.MaybeHideActivityTraces, as: Filter

  setup do
    on_exit(fn -> Filter.install!() end)
    :ok
  end

  test "re-installs the primary filter after OTP removes it" do
    # What OTP does when a primary filter raises.
    :ok = :logger.remove_primary_filter(Filter.filter_id())
    refute Filter.installed?()

    {:ok, log} = with_log(fn -> Watchdog.check_now() end)

    assert Filter.installed?()
    assert log =~ "logger filter was missing"
    assert log =~ "has been re-installed"
  end

  test "a check with the filter present is a no-op" do
    assert Filter.installed?()

    {:ok, log} = with_log(fn -> Watchdog.check_now() end)

    assert Filter.installed?()
    refute log =~ "has been re-installed"
  end

  test "rejects an invalid :check_interval" do
    assert {:error, {%ArgumentError{}, _stacktrace}} =
             GenServer.start(Watchdog, check_interval: :not_an_interval)
  end

  test "an unexpected message does not kill the watchdog" do
    pid = Process.whereis(Watchdog)
    send(pid, :something_unexpected)

    # The call round-trips through the same mailbox after the message above.
    assert :ok = Watchdog.check_now()
    assert Process.alive?(pid)
  end
end
