defmodule Sanbase.RequestContextTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.RequestContext

  setup do
    protected = insert(:user)
    Sanbase.PrivacyCacheSeed.seed!([protected.id])
    {:ok, protected: protected}
  end

  describe "anonymous/1" do
    test "builds a non-protected ctx tagged with the given origin" do
      ctx = RequestContext.anonymous(:graphql)

      assert %RequestContext{origin: :graphql, user_id: nil, activity_traces_hidden: false} = ctx
      refute RequestContext.activity_traces_hidden?(ctx)
    end

    test "supports every documented origin" do
      for origin <- [:graphql, :mcp, :oban, :script, :system, :anonymous] do
        assert %RequestContext{origin: ^origin} = RequestContext.anonymous(origin)
      end
    end
  end

  describe "activity_traces_hidden?/1" do
    test "true only for ctx with activity_traces_hidden: true" do
      assert RequestContext.activity_traces_hidden?(%RequestContext{
               origin: :graphql,
               activity_traces_hidden: true
             })

      refute RequestContext.activity_traces_hidden?(%RequestContext{
               origin: :graphql,
               activity_traces_hidden: false
             })

      refute RequestContext.activity_traces_hidden?(nil)
      refute RequestContext.activity_traces_hidden?(%{activity_traces_hidden: true})
    end
  end

  describe "from_conn/1" do
    test "extracts user_id, auth_method, product_code from san_authentication private" do
      conn =
        Plug.Test.conn(:post, "/graphql")
        |> Plug.Conn.put_private(:san_authentication, %{
          auth: %{auth_method: :apikey, current_user: %{id: 123}},
          product_code: "SANAPI"
        })
        |> Map.put(:remote_ip, {127, 0, 0, 1})

      ctx = RequestContext.from_conn(conn)

      assert ctx.origin == :graphql
      assert ctx.user_id == 123
      assert ctx.auth_method == :apikey
      assert ctx.product_code == "SANAPI"
      assert ctx.remote_ip == "127.0.0.1"
      refute ctx.activity_traces_hidden
    end

    test "anonymous conn (no san_authentication) returns nil user_id, non-protected" do
      conn = Plug.Test.conn(:post, "/graphql")
      ctx = RequestContext.from_conn(conn)

      assert ctx.origin == :graphql
      assert ctx.user_id == nil
      refute ctx.activity_traces_hidden
    end

    test "activity_traces_hidden set when user_id matches the protected set", %{protected: user} do
      conn =
        Plug.Test.conn(:post, "/graphql")
        |> Plug.Conn.put_private(:san_authentication, %{
          auth: %{auth_method: :user_token, current_user: %{id: user.id}},
          product_code: "SANBASE"
        })

      ctx = RequestContext.from_conn(conn)

      assert ctx.user_id == user.id
      assert ctx.activity_traces_hidden
      assert RequestContext.activity_traces_hidden?(ctx)
    end

    test "reads request_id from Logger.metadata set by Plug.RequestId" do
      Logger.metadata(request_id: "abc-123")
      on_exit(fn -> Logger.metadata(request_id: nil) end)

      conn = Plug.Test.conn(:post, "/graphql")
      ctx = RequestContext.from_conn(conn)
      assert ctx.request_id == "abc-123"
    end
  end

  describe "from_mcp_frame/1" do
    test "extracts user_id from frame.assigns[:current_user]" do
      frame = %{
        assigns: %{current_user: %{id: 77}},
        context: %{headers: []}
      }

      ctx = RequestContext.from_mcp_frame(frame)

      assert ctx.origin == :mcp
      assert ctx.user_id == 77
      assert ctx.product_code == "SANAPI"
      refute ctx.activity_traces_hidden
    end

    test "anonymous (no current_user) → nil user_id, non-protected" do
      frame = %{assigns: %{}, context: %{headers: []}}
      ctx = RequestContext.from_mcp_frame(frame)

      assert ctx.origin == :mcp
      assert ctx.user_id == nil
      refute ctx.activity_traces_hidden
    end

    test "activity_traces_hidden for protected user_id", %{protected: user} do
      frame = %{assigns: %{current_user: %{id: user.id}}, context: %{headers: []}}

      ctx = RequestContext.from_mcp_frame(frame)

      assert ctx.user_id == user.id
      assert ctx.activity_traces_hidden
    end

    test "reads request_id from x-request-id / mcp-session-id headers" do
      frame = %{assigns: %{}, context: %{headers: [{"x-request-id", "rid-42"}]}}
      assert RequestContext.from_mcp_frame(frame).request_id == "rid-42"

      frame2 = %{assigns: %{}, context: %{headers: [{"mcp-session-id", "sid-7"}]}}
      assert RequestContext.from_mcp_frame(frame2).request_id == "sid-7"
    end
  end
end
