defmodule Sanbase.Accounts.User.EmailTest do
  use SanbaseWeb.ConnCase, async: true

  alias Sanbase.Accounts.User.Email

  describe "add_redirect_url/3" do
    test "accepts sanbase:// scheme with any path" do
      query_map = %{}

      assert {:ok, %{success_redirect_url: "sanbase://home"}} =
               Email.add_redirect_url(query_map, :success_redirect_url, "sanbase://home")

      assert {:ok, %{success_redirect_url: "sanbase://portfolio/btc"}} =
               Email.add_redirect_url(
                 query_map,
                 :success_redirect_url,
                 "sanbase://portfolio/btc"
               )

      assert {:ok, %{fail_redirect_url: "sanbase://settings"}} =
               Email.add_redirect_url(query_map, :fail_redirect_url, "sanbase://settings")

      assert {:ok, %{fail_redirect_url: "sanbase://login"}} =
               Email.add_redirect_url(query_map, :fail_redirect_url, "sanbase://login")

      assert {:ok, %{success_redirect_url: "sanbase://deep/nested/path"}} =
               Email.add_redirect_url(
                 query_map,
                 :success_redirect_url,
                 "sanbase://deep/nested/path"
               )
    end

    test "accepts valid https santiment.net URLs" do
      query_map = %{}

      assert {:ok, %{success_redirect_url: "https://santiment.net"}} =
               Email.add_redirect_url(query_map, :success_redirect_url, "https://santiment.net")

      assert {:ok, %{success_redirect_url: "https://app.santiment.net"}} =
               Email.add_redirect_url(
                 query_map,
                 :success_redirect_url,
                 "https://app.santiment.net"
               )

      assert {:ok, %{success_redirect_url: "https://app.santiment.net/dashboard"}} =
               Email.add_redirect_url(
                 query_map,
                 :success_redirect_url,
                 "https://app.santiment.net/dashboard"
               )

      assert {:ok, %{fail_redirect_url: "https://insights.santiment.net"}} =
               Email.add_redirect_url(
                 query_map,
                 :fail_redirect_url,
                 "https://insights.santiment.net"
               )

      assert {:ok, %{fail_redirect_url: "https://queries.santiment.net"}} =
               Email.add_redirect_url(
                 query_map,
                 :fail_redirect_url,
                 "https://queries.santiment.net"
               )

      assert {:ok, %{success_redirect_url: "https://app-stage.santiment.net"}} =
               Email.add_redirect_url(
                 query_map,
                 :success_redirect_url,
                 "https://app-stage.santiment.net"
               )
    end

    test "rejects invalid schemes" do
      query_map = %{}

      assert {:error, :invalid_redirect_url, "Invalid success_redirect_url: http://santiment.net"} =
               Email.add_redirect_url(
                 query_map,
                 :success_redirect_url,
                 "http://santiment.net"
               )

      assert {:error, :invalid_redirect_url, "Invalid fail_redirect_url: ftp://santiment.net"} =
               Email.add_redirect_url(query_map, :fail_redirect_url, "ftp://santiment.net")

      assert {:error, :invalid_redirect_url,
              "Invalid success_redirect_url: mailto:test@santiment.net"} =
               Email.add_redirect_url(
                 query_map,
                 :success_redirect_url,
                 "mailto:test@santiment.net"
               )
    end

    test "rejects invalid hosts" do
      query_map = %{}

      assert {:error, :invalid_redirect_url, "Invalid success_redirect_url: https://example.com"} =
               Email.add_redirect_url(query_map, :success_redirect_url, "https://example.com")

      assert {:error, :invalid_redirect_url, "Invalid fail_redirect_url: https://malicious.net"} =
               Email.add_redirect_url(query_map, :fail_redirect_url, "https://malicious.net")

      assert {:error, :invalid_redirect_url,
              "Invalid success_redirect_url: https://santiment.com"} =
               Email.add_redirect_url(query_map, :success_redirect_url, "https://santiment.com")
    end

    test "rejects malformed URLs" do
      query_map = %{}

      assert {:error, :invalid_redirect_url, "Invalid success_redirect_url: not-a-url"} =
               Email.add_redirect_url(query_map, :success_redirect_url, "not-a-url")

      assert {:error, :invalid_redirect_url, "Invalid fail_redirect_url: //example.com"} =
               Email.add_redirect_url(query_map, :fail_redirect_url, "//example.com")
    end

    test "handles nil URLs correctly" do
      query_map = %{existing: "value"}

      assert {:ok, %{existing: "value"}} =
               Email.add_redirect_url(query_map, :success_redirect_url, nil)

      assert {:ok, %{existing: "value"}} =
               Email.add_redirect_url(query_map, :fail_redirect_url, nil)
    end

    test "preserves existing query map values" do
      query_map = %{existing_key: "existing_value", another: "value"}

      assert {:ok,
              %{
                existing_key: "existing_value",
                another: "value",
                success_redirect_url: "sanbase://home"
              }} = Email.add_redirect_url(query_map, :success_redirect_url, "sanbase://home")

      assert {:ok,
              %{
                existing_key: "existing_value",
                another: "value",
                fail_redirect_url: "https://app.santiment.net"
              }} =
               Email.add_redirect_url(query_map, :fail_redirect_url, "https://app.santiment.net")
    end
  end
end
