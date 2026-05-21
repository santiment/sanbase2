defmodule SanbaseWeb.Plug.RequestContextPlugTest do
  # Manipulates Logger.metadata, Process dict, and Sentry.Context — must
  # be serial.
  use ExUnit.Case, async: false

  alias Sanbase.RequestContext
  alias SanbaseWeb.Plug.RequestContextPlug

  @legacy_key :__graphql_query_current_user_id__

  setup do
    on_exit(fn ->
      Logger.reset_metadata([])
      Process.delete(@legacy_key)
      Sentry.Context.clear_all()
    end)

    :ok
  end

  test "clears stale Logger metadata, Process dict, and Sentry.Context" do
    Logger.metadata(
      request_context: %RequestContext{origin: :graphql, user_id: 1},
      hide_user_activity: true,
      user_id: 1
    )

    Process.put(@legacy_key, 1)
    Sentry.Context.set_user_context(%{id: 1})

    conn = Plug.Test.conn(:post, "/graphql")
    _conn = RequestContextPlug.call(conn, [])

    meta = Logger.metadata()
    assert Keyword.get(meta, :request_context) == nil
    assert Keyword.get(meta, :hide_user_activity) == nil
    assert Keyword.get(meta, :user_id) == nil
    assert Process.get(@legacy_key) == nil
    assert Sentry.Context.get_all().user == %{}
  end

  test "preserves :request_id Logger metadata set by Plug.RequestId" do
    # Plug.RequestId mounts BEFORE this plug — the plug must not wipe
    # the request id it set.
    Logger.metadata(request_id: "req-abc")

    conn = Plug.Test.conn(:post, "/graphql")
    _conn = RequestContextPlug.call(conn, [])

    assert Keyword.get(Logger.metadata(), :request_id) == "req-abc"
  end

  test "assigns anonymous :graphql placeholder on conn.assigns" do
    conn = Plug.Test.conn(:post, "/graphql")
    conn = RequestContextPlug.call(conn, [])

    assert %RequestContext{origin: :graphql, user_id: nil, privacy_protected: false} =
             conn.assigns.request_context
  end
end
