defmodule SanbaseWeb.Graphql.SansheetsHelper do
  @moduledoc """
  Helper module for detecting SanSheets requests.

  SanSheets is identified by checking the User-Agent header for:
  1. "Sansheets/" prefix (new, explicit identification)
  2. "Google-Apps-Script" (legacy, for backwards compatibility)
  """

  @sansheets_prefix "Sansheets/"
  @legacy_google_apps_script "Google-Apps-Script"

  @spec sansheets_request?(Plug.Conn.t()) :: boolean()
  def sansheets_request?(conn) do
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [user_agent] -> sansheets_user_agent?(user_agent)
      _ -> false
    end
  end

  @spec sansheets_user_agent?(binary()) :: boolean()
  def sansheets_user_agent?(user_agent) when is_binary(user_agent) do
    String.contains?(user_agent, @sansheets_prefix) or
      String.contains?(user_agent, @legacy_google_apps_script)
  end

  def sansheets_user_agent?(_), do: false
end
