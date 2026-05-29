defmodule Sanbase.Logger.MaybeHideActivityTracesTest do
  use ExUnit.Case, async: true

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
end
