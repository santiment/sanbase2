defmodule SanbaseWeb.Graphql.AuthApiTest do
  use SanbaseWeb.ConnCase

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Utils.DateTime, only: [from_iso8601!: 1]

  setup do
    user = insert(:user)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)

    conn = Plug.Test.init_test_session(build_conn(), jwt_tokens)

    %{
      user: user,
      jwt_tokens: jwt_tokens,
      conn: conn
    }
  end

  test "expirted JWT is treated as anon", context do
    {:ok, jwt_tokens} =
      SanbaseWeb.Guardian.get_jwt_tokens(context.user, %{
        access_token_ttl: {0, :seconds},
        refresh_token_ttl: {0, :seconds}
      })

    Process.sleep(1100)

    conn = Plug.Test.init_test_session(build_conn(), jwt_tokens)

    result =
      conn
      |> post("/graphql", query_skeleton("{ currentUser{ id } }"))
      |> json_response(200)

    assert result["data"]["currentUser"] == nil
  end

  test "conn with JWT tokens in sessions works properly", context do
    # Test that when the session contains the access/refresh token, it is
    # properly resolved to the user

    result =
      context.conn
      |> post("/graphql", query_skeleton("{ currentUser{ id } }"))
      |> json_response(200)

    assert result["data"]["currentUser"]["id"] |> Sanbase.Math.to_integer() ==
             context.user.id
  end

  test "the refresh token silently updates the access token", context do
    new_now = DateTime.utc_now() |> DateTime.to_unix() |> Kernel.+(3600)

    Sanbase.Mock.prepare_mock2(&Guardian.timestamp/0, new_now)
    |> Sanbase.Mock.run_with_mocks(fn ->
      new_conn =
        context.conn
        |> post("/graphql", query_skeleton("{ currentUser{ id } }"))

      old_session = Plug.Conn.get_session(context.conn)
      new_session = Plug.Conn.get_session(new_conn)

      # Asser that the access token has been silently updated as 1 hour has
      # passed since it was issued
      assert old_session["refresh_token"] == context.jwt_tokens.refresh_token
      assert old_session["access_token"] == context.jwt_tokens.access_token
      assert new_session["refresh_token"] == context.jwt_tokens.refresh_token
      assert new_session["access_token"] != context.jwt_tokens.access_token
    end)
  end

  test "the refresh token is invalidated after logout", context do
    assert %{"data" => %{"logout" => %{"success" => true}}} =
             context.conn
             |> post("/graphql", mutation_skeleton("mutation{ logout{ success } }"))
             |> json_response(200)

    new_now = DateTime.utc_now() |> DateTime.to_unix() |> Kernel.+(320)

    Sanbase.Mock.prepare_mock2(&Guardian.timestamp/0, new_now)
    |> Sanbase.Mock.run_with_mocks(fn ->
      conn_same_tokens = Plug.Test.init_test_session(build_conn(), context.jwt_tokens)

      result =
        conn_same_tokens
        |> post("/graphql", query_skeleton("{ currentUser{ id } }"))
        |> json_response(200)

      # The access token is expired and the JWT token cannot be used to generate
      # a new one as it is also expired
      assert result["data"]["currentUser"] == nil
    end)
  end

  test "the refresh token cannot issue new access tokens after 4 weeks",
       context do
    # The refresh token TTL is 4 weeks (28 days)
    new_now = DateTime.utc_now() |> DateTime.to_unix() |> Kernel.+(30 * 86_400)

    Sanbase.Mock.prepare_mock2(&Guardian.timestamp/0, new_now)
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        context.conn
        |> post("/graphql", query_skeleton("{ currentUser{ id } }"))
        |> json_response(200)

      # The access token is expired and the JWT token cannot be used to generate
      # a new one as it is also expired
      assert result["data"]["currentUser"] == nil
    end)
  end

  test "destroy sessions when the refresh token is less than 10 minutes old",
       context do
    result =
      context.conn
      |> post("/graphql", mutation_skeleton("mutation { destroyAllSessions }"))
      |> json_response(200)

    assert result["data"]["destroyAllSessions"] == true
  end

  test "cannot destroy sessions when the refresh at older than 10 minutes",
       context do
    # This check is implemented in a sanbase middleware where DateTime.utc_now is used
    new_now = DateTime.utc_now() |> DateTime.add(11 * 60, :second)

    Sanbase.Mock.prepare_mock2(&DateTime.utc_now/0, new_now)
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        context.conn
        |> post(
          "/graphql",
          mutation_skeleton("mutation { destroyAllSessions }")
        )
        |> json_response(200)

      %{"errors" => [%{"message" => error_msg}]} = result

      assert error_msg =~
               """
               Unauthorized. Reason: The authentication must have been done less \
               than 10 minutes ago. Repeat the authentication process and try again.
               """
    end)
  end

  test "get active sessions", context do
    ipad_conn =
      build_conn()
      |> Plug.Conn.put_req_header(
        "user-agent",
        "Mozilla/5.0 (iPad; CPU OS 12_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.1 Mobile/15E148 Safari/604.1"
      )

    mac_conn =
      build_conn()
      |> Plug.Conn.put_req_header(
        "user-agent",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/11.1.2 Safari/605.1.15"
      )

    _ = setup_jwt_auth(ipad_conn, context.user)
    _ = setup_jwt_auth(mac_conn, context.user)

    query = """
    {
      getAuthSessions {
        jti
        type
        createdAt
        expiresAt
        isCurrent
        hasExpired
        client
        lastActiveAt
        platform
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)

    sessions = result["data"]["getAuthSessions"]

    assert length(sessions) == 3
    assert [session1, session2, session3] = sessions

    assert session1["client"] == "unknown"
    assert session1["platform"] == "unknown"
    assert session1["type"] == "refresh"
    assert session1["isCurrent"] == true
    assert session1["hasExpired"] == false
    assert %DateTime{} = from_iso8601!(session1["createdAt"])
    assert %DateTime{} = from_iso8601!(session1["expiresAt"])
    assert %DateTime{} = from_iso8601!(session1["lastActiveAt"])

    assert session2["client"] == "iPad 12.1"
    assert session2["platform"] == "iOS 12"
    assert session2["type"] == "refresh"
    assert session2["isCurrent"] == false
    assert session2["hasExpired"] == false
    assert %DateTime{} = from_iso8601!(session2["createdAt"])
    assert %DateTime{} = from_iso8601!(session2["expiresAt"])
    assert %DateTime{} = from_iso8601!(session2["lastActiveAt"])

    assert session3["client"] == "Safari 11.1.2"
    assert session3["platform"] == "MacOS 10.11.6 El Capitan"
    assert session3["type"] == "refresh"
    assert session3["isCurrent"] == false
    assert session3["hasExpired"] == false
    assert %DateTime{} = from_iso8601!(session3["createdAt"])
    assert %DateTime{} = from_iso8601!(session3["expiresAt"])
    assert %DateTime{} = from_iso8601!(session3["lastActiveAt"])
  end

  test "logout clears session", %{conn: conn} do
    query = """
    mutation {
      logout {
        success
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    assert json_response(result, 200)["data"]["logout"]["success"]
    assert result.private.plug_session_info == :drop
  end

  describe "access and refresh token behavior after logout" do
    test "refresh token is deleted from DB after logout", context do
      # Before logout: refresh token exists in DB
      {:ok, sessions_before} =
        SanbaseWeb.Guardian.Token.refresh_tokens(context.user.id)

      assert length(sessions_before) == 1

      # Logout
      assert %{"data" => %{"logout" => %{"success" => true}}} =
               context.conn
               |> post("/graphql", mutation_skeleton("mutation{ logout{ success } }"))
               |> json_response(200)

      # After logout: refresh token is removed from DB
      {:ok, sessions_after} =
        SanbaseWeb.Guardian.Token.refresh_tokens(context.user.id)

      assert sessions_after == []
    end

    test "revoked refresh token cannot be exchanged for a new access token", context do
      refresh_token = context.jwt_tokens.refresh_token

      # Logout revokes the refresh token
      assert %{"data" => %{"logout" => %{"success" => true}}} =
               context.conn
               |> post("/graphql", mutation_skeleton("mutation{ logout{ success } }"))
               |> json_response(200)

      # Directly attempt to exchange the revoked refresh token for an access token.
      # This must fail because the refresh token is no longer in the DB.
      opts = [ttl: SanbaseWeb.Guardian.access_token_ttl()]

      assert {:error, _} =
               SanbaseWeb.Guardian.exchange(refresh_token, "refresh", "access", opts)
    end

    test "after logout, access token still works within its 5-min TTL (stateless JWT)", context do
      access_token = context.jwt_tokens.access_token

      # Logout - revokes refresh token and drops session
      assert %{"data" => %{"logout" => %{"success" => true}}} =
               context.conn
               |> post("/graphql", mutation_skeleton("mutation{ logout{ success } }"))
               |> json_response(200)

      # Build a new connection with only the (still valid) access token.
      # The access token is a stateless JWT, so it remains valid until it expires.
      conn_with_old_access =
        build_conn()
        |> Plug.Test.init_test_session(%{access_token: access_token, refresh_token: nil})

      result =
        conn_with_old_access
        |> post("/graphql", query_skeleton("{ currentUser{ id } }"))
        |> json_response(200)

      # The access token is still valid (not expired yet), so the user is authenticated
      assert result["data"]["currentUser"]["id"] |> Sanbase.Math.to_integer() ==
               context.user.id
    end

    test "after logout, expired access token cannot be renewed (refresh token revoked)",
         context do
      # Logout - revokes the refresh token from DB
      assert %{"data" => %{"logout" => %{"success" => true}}} =
               context.conn
               |> post("/graphql", mutation_skeleton("mutation{ logout{ success } }"))
               |> json_response(200)

      # Simulate time passing so the access token expires (6 minutes > 5 min TTL)
      new_now = DateTime.utc_now() |> DateTime.to_unix() |> Kernel.+(360)

      Sanbase.Mock.prepare_mock2(&Guardian.timestamp/0, new_now)
      |> Sanbase.Mock.run_with_mocks(fn ->
        # Build a connection with the original tokens (access expired, refresh revoked)
        conn_with_old_tokens =
          Plug.Test.init_test_session(build_conn(), context.jwt_tokens)

        result =
          conn_with_old_tokens
          |> post("/graphql", query_skeleton("{ currentUser{ id } }"))
          |> json_response(200)

        # Access token expired + refresh token revoked = anonymous user
        assert result["data"]["currentUser"] == nil
      end)
    end

    test "destroyCurrentSession revokes only the current refresh token", context do
      # Create a second session for the same user
      {:ok, second_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(context.user)

      {:ok, sessions_before} =
        SanbaseWeb.Guardian.Token.refresh_tokens(context.user.id)

      assert length(sessions_before) == 2

      # Destroy only the current session (the one from context.conn)
      result =
        context.conn
        |> post("/graphql", mutation_skeleton("mutation{ destroyCurrentSession }"))
        |> json_response(200)

      assert result["data"]["destroyCurrentSession"] == true

      # Only one session remains (the second one)
      {:ok, sessions_after} =
        SanbaseWeb.Guardian.Token.refresh_tokens(context.user.id)

      assert length(sessions_after) == 1

      # The remaining session's JWT is the second token, not the original
      [remaining] = sessions_after
      assert remaining.jti != nil

      # The second token can still be exchanged for a new access token
      opts = [ttl: SanbaseWeb.Guardian.access_token_ttl()]

      assert {:ok, _old, {_new_access_token, _claims}} =
               SanbaseWeb.Guardian.exchange(
                 second_tokens.refresh_token,
                 "refresh",
                 "access",
                 opts
               )
    end

    test "destroyAllSessions revokes all refresh tokens, none can be renewed", context do
      # Create additional sessions
      {:ok, second_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(context.user)
      {:ok, third_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(context.user)

      {:ok, sessions_before} =
        SanbaseWeb.Guardian.Token.refresh_tokens(context.user.id)

      assert length(sessions_before) == 3

      # Destroy all sessions
      result =
        context.conn
        |> post("/graphql", mutation_skeleton("mutation{ destroyAllSessions }"))
        |> json_response(200)

      assert result["data"]["destroyAllSessions"] == true

      # No sessions remain
      {:ok, sessions_after} =
        SanbaseWeb.Guardian.Token.refresh_tokens(context.user.id)

      assert sessions_after == []

      # None of the refresh tokens can be exchanged
      opts = [ttl: SanbaseWeb.Guardian.access_token_ttl()]

      assert {:error, _} =
               SanbaseWeb.Guardian.exchange(
                 second_tokens.refresh_token,
                 "refresh",
                 "access",
                 opts
               )

      assert {:error, _} =
               SanbaseWeb.Guardian.exchange(
                 third_tokens.refresh_token,
                 "refresh",
                 "access",
                 opts
               )
    end
  end
end
