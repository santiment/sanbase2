defmodule Sanbase.Logger.MaybeHideActivityTracesTest do
  # async: false — manipulates Logger.metadata; the application-installed
  # `:logger.primary_filter` is shared across the BEAM, so concurrent
  # tests changing :request_context could interfere with each other.
  use ExUnit.Case, async: false

  require Logger

  import ExUnit.CaptureLog

  alias Sanbase.Logger.MaybeHideActivityTraces, as: Filter
  alias Sanbase.RequestContext

  defp event(msg, meta), do: %{msg: msg, meta: meta, level: :info}

  defp protected_meta() do
    %{
      request_context: %RequestContext{
        origin: :graphql,
        user_id: 1,
        activity_traces_hidden: true
      }
    }
  end

  defp safe_meta() do
    %{
      request_context: %RequestContext{
        origin: :graphql,
        user_id: 2,
        activity_traces_hidden: false
      }
    }
  end

  describe "filter/2" do
    test "drops ABSINTHE :string events when request_context flags protected" do
      ev = event({:string, "ABSINTHE schema=Sanbase op=foo"}, protected_meta())
      assert Filter.filter(ev, []) == :stop
    end

    test "keeps non-Absinthe :string events even when protected" do
      ev = event({:string, "something else"}, protected_meta())
      assert Filter.filter(ev, []) == :ignore
    end

    test "drops ABSINTHE format/args events when protected" do
      ev = event({~c"~s schema=~s", [~c"ABSINTHE", ~c"Sanbase"]}, protected_meta())
      assert Filter.filter(ev, []) == :stop
    end

    test "drops ABSINTHE :report events that have a report_cb" do
      cb = fn _ -> {~c"ABSINTHE schema=~s", [~c"Sanbase"]} end
      ev = event({:report, %{report_cb: cb}}, protected_meta())
      assert Filter.filter(ev, []) == :stop
    end

    test "leaves events alone when no request_context is set" do
      ev = event({:string, "ABSINTHE schema=foo"}, %{})
      assert Filter.filter(ev, []) == :ignore
    end

    test "leaves events alone when request_context says not protected" do
      ev = event({:string, "ABSINTHE schema=foo"}, safe_meta())
      assert Filter.filter(ev, []) == :ignore
    end
  end

  describe "primary filter installed at application startup" do
    setup do
      # Ensure no leakage from other tests.
      Logger.reset_metadata([])
      on_exit(fn -> Logger.reset_metadata([]) end)

      # Re-installing isn't ideal under async, but we run async: false. We
      # also tolerate the filter being absent in cases where the test was
      # invoked without the full app supervisor — re-add idempotently.
      _ =
        :logger.add_primary_filter(
          :sanbase_maybe_hide_activity_traces,
          {&Filter.filter/2, []}
        )

      :ok
    end

    test "protected user: ABSINTHE log line is dropped end-to-end" do
      Logger.metadata(
        request_context: %RequestContext{
          origin: :graphql,
          user_id: 1,
          activity_traces_hidden: true
        }
      )

      log =
        capture_log(fn ->
          Logger.info("ABSINTHE schema=Sanbase op=Sensitive")
        end)

      refute log =~ "ABSINTHE"
      refute log =~ "Sensitive"
    end

    test "non-protected user: ABSINTHE log line passes through" do
      Logger.metadata(
        request_context: %RequestContext{
          origin: :graphql,
          user_id: 2,
          activity_traces_hidden: false
        }
      )

      log =
        capture_log(fn ->
          Logger.info("ABSINTHE schema=Sanbase op=Public")
        end)

      assert log =~ "ABSINTHE"
      assert log =~ "Public"
    end

    test "no request_context: ABSINTHE log line passes through" do
      log = capture_log(fn -> Logger.info("ABSINTHE schema=Sanbase op=Anon") end)
      assert log =~ "ABSINTHE"
    end
  end
end
