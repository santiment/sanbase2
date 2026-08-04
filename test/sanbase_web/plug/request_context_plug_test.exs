defmodule SanbaseWeb.Plug.RequestContextPlugTest do
  # Manipulates Logger.metadata and Sentry.Context — must be serial.
  use ExUnit.Case, async: false

  alias Sanbase.RequestContext
  alias SanbaseWeb.Plug.RequestContextPlug

  setup do
    on_exit(fn ->
      Logger.reset_metadata([])
      Sentry.Context.clear_all()
    end)

    :ok
  end

  test "clears stale Logger metadata and Sentry.Context" do
    Logger.metadata(
      request_context: %RequestContext{origin: :graphql, user_id: 1, activity_traces_hidden: true},
      user_id: 1
    )

    Sentry.Context.set_user_context(%{id: 1})

    conn = Plug.Test.conn(:post, "/graphql")
    _conn = RequestContextPlug.call(conn, [])

    meta = Logger.metadata()
    assert Keyword.get(meta, :request_context) == nil
    assert Keyword.get(meta, :user_id) == nil
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

  describe ":request_id sanitization" do
    test "strips quotes and other characters that could escape a SQL literal" do
      Logger.metadata(request_id: "aaaaaaaaaaaaaaaaaaaa',readonly=0 --")

      _conn = RequestContextPlug.call(Plug.Test.conn(:post, "/graphql"), [])

      request_id = Keyword.get(Logger.metadata(), :request_id)
      refute request_id =~ "'"
      refute request_id =~ " "
      refute request_id =~ ","
    end

    test "an id made entirely of disallowed characters becomes nil rather than empty" do
      Logger.metadata(request_id: String.duplicate("'", 25))

      _conn = RequestContextPlug.call(Plug.Test.conn(:post, "/graphql"), [])

      assert Keyword.get(Logger.metadata(), :request_id) == nil
    end

    test "leaves a normal generated request id untouched" do
      # The shape Plug.RequestId generates itself.
      Logger.metadata(request_id: "GMdnNww9RaXJ5xUAACVh")

      _conn = RequestContextPlug.call(Plug.Test.conn(:post, "/graphql"), [])

      assert Keyword.get(Logger.metadata(), :request_id) == "GMdnNww9RaXJ5xUAACVh"
    end
  end

  test "assigns anonymous :graphql placeholder on conn.assigns" do
    conn = Plug.Test.conn(:post, "/graphql")
    conn = RequestContextPlug.call(conn, [])

    assert %RequestContext{origin: :graphql, user_id: nil, activity_traces_hidden: false} =
             conn.assigns.request_context
  end
end
