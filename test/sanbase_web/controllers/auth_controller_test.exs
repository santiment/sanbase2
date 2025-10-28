defmodule SanbaseWeb.AuthControllerTest do
  use SanbaseWeb.ConnCase, async: false

  alias SanbaseWeb.AuthController

  @moduletag capture_log: true

  describe "validate_redirect_url/1" do
    test "accepts sanbase:// scheme with any path" do
      assert AuthController.validate_redirect_url("sanbase://home") == true
      assert AuthController.validate_redirect_url("sanbase://portfolio/btc") == true
      assert AuthController.validate_redirect_url("sanbase://settings") == true
      assert AuthController.validate_redirect_url("sanbase://login") == true
      assert AuthController.validate_redirect_url("sanbase://deep/nested/path") == true
    end

    test "accepts valid https santiment.net URLs" do
      assert AuthController.validate_redirect_url("https://santiment.net") == true
      assert AuthController.validate_redirect_url("https://app.santiment.net") == true
      assert AuthController.validate_redirect_url("https://app.santiment.net/dashboard") == true
      assert AuthController.validate_redirect_url("https://insights.santiment.net") == true
      assert AuthController.validate_redirect_url("https://queries.santiment.net") == true
      assert AuthController.validate_redirect_url("https://app-stage.santiment.net") == true
    end

    test "rejects invalid schemes" do
      assert AuthController.validate_redirect_url("http://santiment.net") ==
               {:error, "Invalid redirect URL"}

      assert AuthController.validate_redirect_url("ftp://santiment.net") ==
               {:error, "Invalid redirect URL"}

      assert AuthController.validate_redirect_url("mailto:test@santiment.net") ==
               {:error, "Invalid redirect URL"}
    end

    test "rejects invalid hosts" do
      assert AuthController.validate_redirect_url("https://example.com") ==
               {:error, "Invalid redirect URL"}

      assert AuthController.validate_redirect_url("https://malicious.net") ==
               {:error, "Invalid redirect URL"}

      assert AuthController.validate_redirect_url("https://santiment.com") ==
               {:error, "Invalid redirect URL"}
    end

    test "rejects malformed URLs" do
      assert AuthController.validate_redirect_url("not-a-url") ==
               {:error, "Invalid redirect URL"}

      assert AuthController.validate_redirect_url("//example.com") ==
               {:error, "Invalid redirect URL"}
    end
  end
end
