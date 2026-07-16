defmodule Sanbase.Hyperliquid.Bbo.QuarantineTest do
  use ExUnit.Case, async: false

  alias Sanbase.Hyperliquid.Bbo.Quarantine

  @moduletag capture_log: true

  setup do
    original = Application.get_env(:sanbase, Quarantine)

    on_exit(fn ->
      if is_nil(original),
        do: Application.delete_env(:sanbase, Quarantine),
        else: Application.put_env(:sanbase, Quarantine, original)
    end)

    :ok
  end

  defp put_ignored(value) do
    Application.put_env(:sanbase, Quarantine, ignored_coins: value)
  end

  defp put_config(kv) do
    Application.put_env(:sanbase, Quarantine, kv)
  end

  describe "enabled?/0" do
    test "enabled by default when unset" do
      Application.delete_env(:sanbase, Quarantine)
      assert Quarantine.enabled?()
    end

    test "explicit false or 0 disables" do
      put_config(enabled?: "false")
      refute Quarantine.enabled?()

      put_config(enabled?: "0")
      refute Quarantine.enabled?()
    end

    test "garbage value falls back to enabled" do
      put_config(enabled?: "banana")
      assert Quarantine.enabled?()
    end
  end

  describe "disabled workflow" do
    test "handle_crash, probate and probe_tick are no-ops" do
      put_config(enabled?: "false", ignored_coins: "")
      now = 1_000_000
      sends = [%{coin: "X", sent_at_ms: now - 100}]

      q = %Quarantine{recent_sends: sends}
      assert Quarantine.handle_crash(q, MapSet.new(), now) == q

      assert Quarantine.probate(Quarantine.new(), ["X"], "why").probation == []

      q = %Quarantine{probation: ["X"]}
      assert {^q, :noop} = Quarantine.probe_tick(q, MapSet.new(), 60_000, true, now)
    end

    test "audit exclusions and ignored coins still apply when disabled" do
      put_config(enabled?: "false", ignored_coins: "ANSEM")

      excluded = Quarantine.excluded(%Quarantine{audit_excluded: %{"SPOT" => "r"}})

      assert Map.has_key?(excluded, "ANSEM")
      assert Map.has_key?(excluded, "SPOT")
    end
  end

  describe "ignored_coins/0" do
    test "parses the comma-separated env value, trimming blanks" do
      put_ignored(" ANSEM, FOO ,, ")

      assert Quarantine.ignored_coins() == %{
               "ANSEM" => "ignored via HYPERLIQUID_IGNORED_COINS",
               "FOO" => "ignored via HYPERLIQUID_IGNORED_COINS"
             }
    end

    test "empty or missing config means nothing ignored" do
      put_ignored("")
      assert Quarantine.ignored_coins() == %{}
    end
  end

  describe "excluded/1" do
    test "merges env ignores, audit verdicts and convictions" do
      put_ignored("ANSEM")

      q = %Quarantine{
        audit_excluded: %{"SPOT" => "spot token only"},
        quarantined: %{"KILLER" => "probe conviction"}
      }

      assert Quarantine.excluded(q) == %{
               "ANSEM" => "ignored via HYPERLIQUID_IGNORED_COINS",
               "SPOT" => "spot token only",
               "KILLER" => "probe conviction"
             }
    end
  end

  describe "probe lifecycle" do
    test "full path: crash -> probation -> pipelined probes -> strikes -> conviction" do
      put_ignored("")
      now = 1_000_000
      sends = [%{coin: "X", sent_at_ms: now - 100}, %{coin: "OK", sent_at_ms: now - 300}]

      # Crash with X and OK unconfirmed: both on probation.
      q = Quarantine.handle_crash(%Quarantine{recent_sends: sends}, MapSet.new(), now)
      assert q.probation == ["X", "OK"]

      # Settled connection: probe starts with the head coin.
      {q, {:subscribe, "X"}} = Quarantine.probe_tick(q, MapSet.new(), 60_000, true, now)
      assert Quarantine.probing_coins(q) == ["X"]

      # Crash 250ms after the probe (the observed kill lag): strike 1,
      # X re-queued behind OK.
      q = Quarantine.handle_crash(%{q | recent_sends: []}, MapSet.new(), now + 250)
      assert q.probation == ["OK", "X"]
      assert q.probe_strikes == %{"X" => 1}
      refute Map.has_key?(q.quarantined, "X")

      # Pipelining: X's second probe starts one spacing after OK's, without
      # waiting for OK's verdict.
      {q, {:subscribe, "OK"}} = Quarantine.probe_tick(q, MapSet.new(), 60_000, true, now + 1_000)
      {q, :noop} = Quarantine.probe_tick(q, MapSet.new(), 60_000, true, now + 1_300)

      {q, {:subscribe, "X"}} =
        Quarantine.probe_tick(q, MapSet.new(), 60_000, true, now + 2_500)

      assert Quarantine.probing_coins(q) == ["X", "OK"]

      # Crash 250ms after X's probe: only X (age 250 <= strike window) is
      # struck -> convicted; OK's older probe (age 1750 > strike window) is
      # not blamed and stays on probation for a clean re-probe.
      q = Quarantine.handle_crash(%{q | recent_sends: []}, MapSet.new(), now + 2_750)

      assert Map.get(q.quarantined, "X") =~ "probe conviction"
      assert q.probation == ["OK"]
      assert q.probe_strikes == %{}

      # OK re-probes and survives with confirmation: cleared.
      {q, {:subscribe, "OK"}} = Quarantine.probe_tick(q, MapSet.new(), 60_000, true, now + 3_000)
      {q, :noop} = Quarantine.probe_tick(q, MapSet.new(["OK"]), 60_000, true, now + 5_100)

      assert q.probation == []
      assert Quarantine.probing_coins(q) == []
    end

    test "probe that never confirms is quarantined as silently ignored" do
      put_ignored("")
      q = %Quarantine{probation: ["X"], probing: [%{coin: "X", started_ms: 0}]}

      {q, :noop} = Quarantine.probe_tick(q, MapSet.new(), 60_000, true, 20_000)

      assert q.probation == []
      assert Map.get(q.quarantined, "X") =~ "never confirmed"
    end

    test "crash long after the probe is not attributed to it" do
      put_ignored("")
      q = %Quarantine{probation: ["X"], probing: [%{coin: "X", started_ms: 0}]}

      q = Quarantine.handle_crash(%{q | recent_sends: []}, MapSet.new(), 60_000)

      assert q.probing == []
      assert q.probe_strikes == %{}
      assert q.probation == ["X"]
    end

    test "no probe starts on a young connection or a draining queue" do
      put_ignored("")
      q = %Quarantine{probation: ["X"]}

      assert {^q, :noop} = Quarantine.probe_tick(q, MapSet.new(), 1_000, true, 0)
      assert {^q, :noop} = Quarantine.probe_tick(q, MapSet.new(), 60_000, false, 0)
    end

    test "the strike clock restarts when the probe frame is actually sent" do
      put_ignored("")
      # Probe queued at t=0; the send only happens at t=1400.
      q = %Quarantine{probation: ["X"], probing: [%{coin: "X", started_ms: 0}]}
      q = Quarantine.track_send(q, "X", [], 1_400)

      # Kill lands 300ms after the send (t=1700). Measured from queue time
      # that is outside the strike window — the send-time restart is what
      # keeps the kill attributable.
      q = Quarantine.handle_crash(q, MapSet.new(), 1_700)

      assert q.probe_strikes == %{"X" => 1}
      assert q.probation == ["X"]
    end

    test "no new probe before the spacing since the newest in-flight one" do
      put_ignored("")
      q = %Quarantine{probation: ["A", "B"], probing: [%{coin: "A", started_ms: 1_000}]}

      # 300ms after A's probe: too soon for B.
      {q, :noop} = Quarantine.probe_tick(q, MapSet.new(), 60_000, true, 1_300)
      # A full spacing after: B starts while A still awaits its verdict.
      {q, {:subscribe, "B"}} = Quarantine.probe_tick(q, MapSet.new(), 60_000, true, 2_500)

      assert Quarantine.probing_coins(q) == ["B", "A"]
    end
  end

  describe "apply_audit/2" do
    test "replaces verdicts and prunes probation" do
      put_ignored("")

      q = %Quarantine{probation: ["BAD", "Y"], audit_excluded: %{"OLD" => "gone"}}
      q = Quarantine.apply_audit(q, %{"BAD" => "spot token only"})

      assert q.audit_excluded == %{"BAD" => "spot token only"}
      assert q.probation == ["Y"]
    end
  end
end
