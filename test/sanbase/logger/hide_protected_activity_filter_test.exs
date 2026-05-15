defmodule Sanbase.Logger.HideProtectedActivityFilterTest do
  use ExUnit.Case, async: true

  alias Sanbase.Logger.HideProtectedActivityFilter, as: Filter

  defp event(msg, meta), do: %{msg: msg, meta: meta, level: :info}

  describe "filter/2" do
    test "drops ABSINTHE :string events when hide_user_activity is set" do
      ev = event({:string, "ABSINTHE schema=Sanbase op=foo"}, %{hide_user_activity: true})
      assert Filter.filter(ev, []) == :stop
    end

    test "keeps non-Absinthe :string events even when hide_user_activity is set" do
      ev = event({:string, "something else"}, %{hide_user_activity: true})
      assert Filter.filter(ev, []) == :ignore
    end

    test "drops ABSINTHE format/args events when hide_user_activity is set" do
      ev = event({~c"~s schema=~s", [~c"ABSINTHE", ~c"Sanbase"]}, %{hide_user_activity: true})
      assert Filter.filter(ev, []) == :stop
    end

    test "drops ABSINTHE :report events that have a report_cb" do
      cb = fn _ -> {~c"ABSINTHE schema=~s", [~c"Sanbase"]} end
      ev = event({:report, %{report_cb: cb}}, %{hide_user_activity: true})
      assert Filter.filter(ev, []) == :stop
    end

    test "leaves events alone when hide_user_activity is not set" do
      ev = event({:string, "ABSINTHE schema=foo"}, %{})
      assert Filter.filter(ev, []) == :ignore
    end

    test "leaves events alone when hide_user_activity is false" do
      ev = event({:string, "ABSINTHE schema=foo"}, %{hide_user_activity: false})
      assert Filter.filter(ev, []) == :ignore
    end
  end
end
