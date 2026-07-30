defmodule Sanbase.ClickhouseRepoTimeoutErrorTest do
  use ExUnit.Case, async: true

  alias Sanbase.ClickhouseRepo

  describe "timeout-class errors" do
    test "Ch/Mint recv timeout" do
      # Mint formats :timeout as exactly this word, so it must match alone.
      assert ClickhouseRepo.timeout_error?("timeout")

      assert ClickhouseRepo.timeout_error?(
               Exception.message(%Mint.TransportError{reason: :timeout})
             )

      assert ClickhouseRepo.timeout_error?(inspect(%Mint.TransportError{reason: :timeout}))
      assert ClickhouseRepo.timeout_error?("tcp recv (idle): timed out")
    end

    test "DBConnection checkout timeout" do
      assert ClickhouseRepo.timeout_error?(
               "client #PID<0.1.0> timed out because it queued and checked out " <>
                 "the connection for longer than 85000ms"
             )
    end

    test "DBConnection queue shedding" do
      assert ClickhouseRepo.timeout_error?(
               "connection not available and request was dropped from queue after 10000ms"
             )
    end

    test "ClickHouse TIMEOUT_EXCEEDED, as transform_error_string/1 rewrites it" do
      assert ClickhouseRepo.timeout_error?(
               "(TIMEOUT_EXCEEDED) Timeout exceeded: elapsed 85.1 seconds, maximum: 85 seconds"
             )

      assert ClickhouseRepo.timeout_error?("Code: 159. DB::Exception: Timeout exceeded")

      # The error code alone, without the prose, is matched on its own.
      assert ClickhouseRepo.timeout_error?("Code: 159. DB::Exception (TIMEOUT_EXCEEDED)")
    end

    test "the timeout phrase still counts when the query is echoed after it" do
      assert ClickhouseRepo.timeout_error?(
               "(TIMEOUT_EXCEEDED) Timeout exceeded: elapsed 85.1 seconds: " <>
                 "while processing query: SELECT value FROM intraday_metrics"
             )
    end
  end

  describe "non-timeout errors" do
    test "ordinary ClickHouse errors" do
      refute ClickhouseRepo.timeout_error?("Code: 60. DB::Exception: Table does not exist")
      refute ClickhouseRepo.timeout_error?("(UNKNOWN_TABLE) Table does not exist")
      refute ClickhouseRepo.timeout_error?("syntax error at position 10")
    end

    test "a query that merely mentions a timeout is not a timeout" do
      refute ClickhouseRepo.timeout_error?(
               "(UNKNOWN_TABLE) Table intraday_metrics does not exist " <>
                 "while processing query: SELECT timeout_ms FROM intraday_metrics"
             )

      # An identifier that starts with "timeout" is not the word "timeout" —
      # the word boundary keeps it out even when it leaks into the error prose.
      refute ClickhouseRepo.timeout_error?("(UNKNOWN_IDENTIFIER) Missing columns: 'timeout_ms'")
      refute ClickhouseRepo.timeout_error?("(UNKNOWN_SETTING) Unknown setting receive_timeout_ms")
    end

    test "non-binary input" do
      refute ClickhouseRepo.timeout_error?(nil)
      refute ClickhouseRepo.timeout_error?(:some_atom)
      refute ClickhouseRepo.timeout_error?(%{message: "timed out"})
    end
  end
end
