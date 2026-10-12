defmodule Sanbase.ClickhouseRepoErrorCodeTest do
  use ExUnit.Case, async: true

  alias Sanbase.ClickhouseRepo

  test "returns the leading ClickHouse error code" do
    assert "UNKNOWN_TABLE" == ClickhouseRepo.error_code("(UNKNOWN_TABLE) Table does not exist")

    assert "ILLEGAL_PREWHERE" ==
             ClickhouseRepo.error_code(
               "[9eaa0d5b-cb52] (ILLEGAL_PREWHERE) Storage View doesn't support PREWHERE."
             )
  end

  test "ignores codes inside the echoed query" do
    assert "TIMEOUT_EXCEEDED" ==
             ClickhouseRepo.error_code(
               "[9eaa0d5b] (TIMEOUT_EXCEEDED) Timeout exceeded: elapsed 85 seconds " <>
                 "while processing query: SELECT (MY_CONST) FROM t"
             )

    assert nil ==
             ClickhouseRepo.error_code(
               "[9eaa0d5b] Cannot execute query while processing query: SELECT (MY_CONST)"
             )
  end

  test "returns nil without an error code" do
    assert nil == ClickhouseRepo.error_code("Template keys missing from the parameters")
    assert nil == ClickhouseRepo.error_code(:timeout)
  end
end
