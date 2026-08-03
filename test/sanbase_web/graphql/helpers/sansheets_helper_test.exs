defmodule SanbaseWeb.Graphql.SansheetsHelperTest do
  use ExUnit.Case, async: true

  alias SanbaseWeb.Graphql.SansheetsHelper

  describe "sansheets_user_agent?/1" do
    test "the Sansheets token is recognized only as a prefix" do
      assert SansheetsHelper.sansheets_user_agent?("Sansheets/1.0")
      assert SansheetsHelper.sansheets_user_agent?("Sansheets/1.0 (some suffix)")

      refute SansheetsHelper.sansheets_user_agent?("Mozilla/5.0 (compatible; Sansheets/1.0)")
      refute SansheetsHelper.sansheets_user_agent?("NotSansheets/1.0")
      refute SansheetsHelper.sansheets_user_agent?("sansheets/1.0")
    end

    test "the legacy Google token is recognized anywhere in the string" do
      # The shape Apps Script sends. It cannot set its own User-Agent, so this
      # arm must stay a substring match.
      assert SansheetsHelper.sansheets_user_agent?(
               "Mozilla/5.0 (compatible; Google-Apps-Script; beanserver; +https://script.google.com)"
             )
    end

    test "an unrelated user agent does not match" do
      refute SansheetsHelper.sansheets_user_agent?("Mozilla/5.0 (Macintosh; Intel Mac OS X)")
      refute SansheetsHelper.sansheets_user_agent?("")
      refute SansheetsHelper.sansheets_user_agent?(nil)
    end
  end

  describe "sansheets_request?/1" do
    test "reads the user-agent header" do
      assert SansheetsHelper.sansheets_request?(conn_with_user_agent("Sansheets/1.0"))
      refute SansheetsHelper.sansheets_request?(conn_with_user_agent("Mozilla/5.0"))
      refute SansheetsHelper.sansheets_request?(Plug.Test.conn(:post, "/graphql"))
    end

    defp conn_with_user_agent(user_agent) do
      Plug.Test.conn(:post, "/graphql") |> Plug.Conn.put_req_header("user-agent", user_agent)
    end
  end
end
