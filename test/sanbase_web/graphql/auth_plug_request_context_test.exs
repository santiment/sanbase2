defmodule SanbaseWeb.Graphql.AuthPlugRequestContextTest do
  # Worker-reuse coverage. Two sequential AuthPlug invocations in the
  # same test process simulate Cowboy reusing a worker — verifies the
  # clearing invariant in `SanbaseWeb.Plug.RequestContextPlug` plus
  # `AuthPlug` together. Must be serial since both Logger.metadata and
  # the process dictionary are touched.
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  alias Sanbase.Accounts
  alias Sanbase.RequestContext
  alias SanbaseWeb.Graphql.{AuthPlug, ContextPlug}
  alias SanbaseWeb.Plug.RequestContextPlug

  @legacy_key :__graphql_query_current_user_id__

  setup do
    Process.delete(@legacy_key)
    Logger.reset_metadata([])
    Sentry.Context.clear_all()

    on_exit(fn ->
      Process.delete(@legacy_key)
      Logger.reset_metadata([])
      Sentry.Context.clear_all()
    end)

    :ok
  end

  defp seed_protected_user() do
    user = insert(:user)
    Sanbase.PrivacyCacheSeed.seed!([user.id])
    user
  end

  defp run_pipeline(conn) do
    conn
    |> RequestContextPlug.call([])
    |> AuthPlug.call(%{})
    |> ContextPlug.call(%{})
  end

  test "AuthPlug builds a RequestContext and threads it to conn.assigns + Absinthe context + Logger.metadata",
       %{conn: conn} do
    user = insert(:user)

    conn =
      conn
      |> get("/get_routed_conn")
      |> setup_jwt_auth(user)
      |> run_pipeline()

    ctx = conn.assigns.request_context
    assert %RequestContext{origin: :graphql, auth_method: :user_token} = ctx
    assert ctx.user_id == user.id
    refute ctx.activity_traces_hidden

    assert conn.private.absinthe.context.request_context == ctx
    assert Keyword.get(Logger.metadata(), :request_context) == ctx
  end

  test "anonymous request gets an anonymous RequestContext (no user_id, not protected)",
       %{conn: conn} do
    conn =
      conn
      |> get("/get_routed_conn")
      |> run_pipeline()

    ctx = conn.assigns.request_context
    assert %RequestContext{origin: :graphql, user_id: nil, activity_traces_hidden: false} = ctx
    refute RequestContext.activity_traces_hidden?(ctx)

    # Absinthe context bridge populated
    assert conn.private.absinthe.context.request_context == ctx
  end

  test "protected user → request_context flagged protected and Sentry user is set", %{conn: conn} do
    user = seed_protected_user()

    conn =
      conn
      |> get("/get_routed_conn")
      |> setup_jwt_auth(user)
      |> run_pipeline()

    assert conn.assigns.request_context.user_id == user.id
    assert conn.assigns.request_context.activity_traces_hidden
    assert Keyword.get(Logger.metadata(), :hide_user_activity) == true
    assert Sentry.Context.get_all().user == %{id: user.id}
  end

  describe "Cowboy worker reuse" do
    test "protected user A → non-protected user B: no state from A survives" do
      protected_user = seed_protected_user()
      safe_user = insert(:user)
      refute Accounts.activity_traces_hidden?(safe_user.id)

      # Request A — protected
      conn_a =
        build_conn()
        |> get("/get_routed_conn")
        |> setup_jwt_auth(protected_user)
        |> run_pipeline()

      assert conn_a.assigns.request_context.activity_traces_hidden
      assert Process.get(@legacy_key) == protected_user.id
      assert Sentry.Context.get_all().user == %{id: protected_user.id}

      # Same process runs request B — non-protected. The clearing
      # invariant lives in RequestContextPlug; everything from A must
      # be wiped before AuthPlug authenticates B.
      conn_b =
        build_conn()
        |> get("/get_routed_conn")
        |> setup_jwt_auth(safe_user)
        |> run_pipeline()

      assert conn_b.assigns.request_context.user_id == safe_user.id
      refute conn_b.assigns.request_context.activity_traces_hidden
      assert Process.get(@legacy_key) == safe_user.id
      assert Keyword.get(Logger.metadata(), :hide_user_activity) == nil
      assert Sentry.Context.get_all().user == %{id: safe_user.id}
    end

    test "protected user A → anonymous request B: B is anonymous, not stuck on A" do
      protected_user = seed_protected_user()

      # Request A — protected
      conn_a =
        build_conn()
        |> get("/get_routed_conn")
        |> setup_jwt_auth(protected_user)
        |> run_pipeline()

      assert conn_a.assigns.request_context.activity_traces_hidden

      # Request B — no auth header
      conn_b =
        build_conn()
        |> get("/get_routed_conn")
        |> run_pipeline()

      assert conn_b.assigns.request_context.user_id == nil
      refute conn_b.assigns.request_context.activity_traces_hidden
      assert Process.get(@legacy_key) == nil
      assert Keyword.get(Logger.metadata(), :hide_user_activity) == nil
      assert Sentry.Context.get_all().user == %{}
    end
  end
end
