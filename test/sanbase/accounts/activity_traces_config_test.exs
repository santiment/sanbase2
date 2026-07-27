defmodule Sanbase.Accounts.ActivityTracesConfigTest do
  use ExUnit.Case, async: false

  alias Sanbase.Accounts.ActivityTracesConfig, as: Config

  doctest Config

  setup do
    original = Application.fetch_env(:sanbase, Config)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:sanbase, Config, value)
        :error -> Application.delete_env(:sanbase, Config)
      end

      Config.reload()
    end)

    :ok
  end

  test "config/0 keys and enabled?/1 agree on the defaults" do
    for {flag, value} <- Config.config() do
      assert Config.enabled?(flag) == value
    end
  end

  test "a runtime override takes effect after reload/0" do
    # Warm the cache so the override is stale until reload.
    Config.reload()
    Application.put_env(:sanbase, Config, hide_logger: false)

    assert Config.enabled?(:hide_logger)

    Config.reload()
    refute Config.enabled?(:hide_logger)
  end

  test "removing the override and reloading restores the defaults" do
    Application.put_env(:sanbase, Config, hide_logger: false)
    Config.reload()
    refute Config.enabled?(:hide_logger)

    Application.delete_env(:sanbase, Config)
    Config.reload()
    assert Config.enabled?(:hide_logger)
  end

  test "flags without an override keep their compile-time default" do
    Application.put_env(:sanbase, Config, hide_logger: false)
    Config.reload()

    assert Config.enabled?(:hide_ch_query_log)
  end

  test "an expired cache entry is rebuilt on the next read" do
    Config.reload()
    Config.expire_cache!()

    Application.put_env(:sanbase, Config, hide_logger: false)
    refute Config.enabled?(:hide_logger)
  end

  test "reload/0 raises on a non-boolean override value" do
    Application.put_env(:sanbase, Config, hide_logger: "false")

    assert_raise ArgumentError, ~r/invalid runtime override/, fn ->
      Config.reload()
    end
  end

  test "reload/0 raises on an unknown override flag" do
    Application.put_env(:sanbase, Config, no_such_flag: true)

    assert_raise ArgumentError, ~r/invalid runtime override/, fn ->
      Config.reload()
    end
  end

  test "enabled?/1 and hidden?/2 raise on an unknown flag" do
    assert_raise FunctionClauseError, fn ->
      Config.enabled?(:no_such_flag)
    end

    assert_raise FunctionClauseError, fn ->
      Config.hidden?(:no_such_flag, nil)
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

    # A disabled flag wins even for a protected context.
    Application.put_env(:sanbase, Config, hide_logger: false)
    Config.reload()
    refute Config.hidden?(:hide_logger, protected)
  end
end
