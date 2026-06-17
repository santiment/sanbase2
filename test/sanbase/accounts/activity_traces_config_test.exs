defmodule Sanbase.Accounts.ActivityTracesConfigTest do
  use ExUnit.Case, async: true

  alias Sanbase.Accounts.ActivityTracesConfig, as: Config

  doctest Config

  test "config/0 keys and enabled?/1 agree" do
    for {flag, value} <- Config.config() do
      assert Config.enabled?(flag) == value
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
