defmodule Sanbase.Accounts.ActivityTracesConfigTest do
  # async: false — these tests mutate the global application env and the
  # persistent-term cache that `enabled?/1` reads.
  use ExUnit.Case, async: false

  alias Sanbase.Accounts.ActivityTracesConfig, as: Config

  doctest Config

  # White-box: the cache key/shape from the module internals, used only
  # to backdate the TTL in tests.
  @pt_key {Config, :resolved_config}

  setup do
    on_exit(fn ->
      Application.delete_env(:sanbase, Config)
      Config.reload()
    end)
  end

  test "config/0 keys and enabled?/1 agree on the defaults" do
    for {flag, value} <- Config.config() do
      assert Config.enabled?(flag) == value
    end
  end

  test "a runtime override takes effect after reload/0" do
    # Warm the cache with the defaults so the override is observably stale.
    Config.reload()
    Application.put_env(:sanbase, Config, hide_logger: false)

    # The cached value is served until the TTL expires or reload/0 runs.
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
    {resolved, _expires_at} = :persistent_term.get(@pt_key)
    :persistent_term.put(@pt_key, {resolved, System.monotonic_time(:millisecond) - 1})

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
