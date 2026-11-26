defmodule SanbaseWeb.Plug.RedactedLoggerTest do
  use ExUnit.Case, async: true

  alias SanbaseWeb.Plug.RedactedLogger

  test "redacts secret path segments" do
    assert RedactedLogger.redact_path("/telegram/s3cr3t") == "/telegram/[REDACTED]"
    assert RedactedLogger.redact_path("/bot/login/s3cr3t") == "/bot/login/[REDACTED]"

    assert RedactedLogger.redact_path("/bot/login/s3cr3t/user") ==
             "/bot/login/[REDACTED]/[REDACTED]"

    assert RedactedLogger.redact_path("/mailjet/webhook/s3cr3t") == "/mailjet/webhook/[REDACTED]"
    assert RedactedLogger.redact_path("/ses/webhook/s3cr3t") == "/ses/webhook/[REDACTED]"

    assert RedactedLogger.redact_path("/santiment_team_members/s3cr3t") ==
             "/santiment_team_members/[REDACTED]"

    assert RedactedLogger.redact_path("/monitored_twitter_handles/s3cr3t") ==
             "/monitored_twitter_handles/[REDACTED]"

    assert RedactedLogger.redact_path("/projects_data_reader_webhook/s3cr3t") ==
             "/projects_data_reader_webhook/[REDACTED]"
  end

  test "leaves other paths untouched" do
    for path <- ["/", "/graphql", "/telegram", "/bot/login", "/mailjet/other/x", "/api/v1/x"] do
      assert RedactedLogger.redact_path(path) == path
    end
  end
end
