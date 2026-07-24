defmodule Sanbase.Accounts.ActivityTracesConfigTest do
  # async: false — these tests mutate the global application env that
  # `enabled?/1` reads.
  use ExUnit.Case, async: false

  alias Sanbase.Accounts.ActivityTracesConfig, as: Config

  doctest Config

  setup do
    on_exit(fn -> Application.delete_env(:sanbase, Config) end)
  end

  test "config/0 keys and enabled?/1 agree" do
    for {flag, value} <- Config.config() do
      assert Config.enabled?(flag) == value
    end
  end

  test "enabled?/1 honors a boolean runtime override" do
    Application.put_env(:sanbase, Config, hide_logger: false)
    refute Config.enabled?(:hide_logger)

    Application.put_env(:sanbase, Config, hide_logger: true)
    assert Config.enabled?(:hide_logger)
  end

  test "enabled?/1 falls back to @config for flags without an override" do
    Application.put_env(:sanbase, Config, hide_logger: false)

    assert Config.enabled?(:hide_ch_query_log)
  end

  test "enabled?/1 raises on a non-boolean runtime override" do
    Application.put_env(:sanbase, Config, hide_logger: "false")

    assert_raise ArgumentError, ~r/expected a boolean runtime override/, fn ->
      Config.enabled?(:hide_logger)
    end
  end

  test "enabled?/1 raises on an unknown flag" do
    assert_raise FunctionClauseError, fn ->
      Config.enabled?(:no_such_flag)
    end
  end

  test "hidden?/2 requires both an enabled flag and a protected context" do
    protected = %Sanbase.RequestContext{origin: :graphql, activity_traces_hidden: true}
    unprotected = %Sanbase.RequestContext{origin: :graphql, activity_traces_hidden: false}

    # `hide_logger` ships enabled, so it tracks the context flag.
    assert Config.enabled?(:hide_logger)
    assert Config.hidden?(:hide_logger, protected)
    refute Config.hidden?(:hide_logger, unprotected)
    refute Config.hidden?(:hide_logger, nil)
  end
end
