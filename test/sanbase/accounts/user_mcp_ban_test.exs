defmodule Sanbase.Accounts.UserMcpBanTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory

  alias Sanbase.Accounts.User

  setup do
    %{user: insert(:user)}
  end

  test "mcp_ban! sets flag, timestamp, and reason", %{user: user} do
    banned = User.mcp_ban!(user, "abuse")

    assert banned.is_mcp_banned == true
    assert banned.mcp_banned_reason == "abuse"
    assert %DateTime{} = banned.mcp_banned_at
  end

  test "mcp_unban! clears the flag and reason", %{user: user} do
    user |> User.mcp_ban!("abuse")
    {:ok, user} = User.by_id(user.id)
    cleared = User.mcp_unban!(user)

    assert cleared.is_mcp_banned == false
    assert cleared.mcp_banned_at == nil
    assert cleared.mcp_banned_reason == nil
  end

  test "mcp_banned?/1 reflects current DB state regardless of cached structs", %{user: user} do
    refute User.mcp_banned?(user.id)
    User.mcp_ban!(user, "abuse")
    assert User.mcp_banned?(user.id)
  end
end
