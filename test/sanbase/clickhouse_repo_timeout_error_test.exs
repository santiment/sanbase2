defmodule Sanbase.ClickhouseRepoTimeoutErrorTest do
  use ExUnit.Case, async: true

  alias Sanbase.ClickhouseRepo

  test "classifies timeout-class errors" do
    assert ClickhouseRepo.timeout_error?(
             "tcp recv (idle): timed out. Client #PID<0.1.0> timed out because it queued"
           )

    assert ClickhouseRepo.timeout_error?(
             "connection not available and request was dropped from queue after 2500ms"
           )

    assert ClickhouseRepo.timeout_error?("Code: 159. DB::Exception: Timeout exceeded")
    assert ClickhouseRepo.timeout_error?("TIMEOUT_EXCEEDED")
    assert ClickhouseRepo.timeout_error?("the query timed out")
  end

  test "does not classify other errors as timeouts" do
    refute ClickhouseRepo.timeout_error?("Code: 60. DB::Exception: Table does not exist")
    refute ClickhouseRepo.timeout_error?("syntax error at position 10")
    refute ClickhouseRepo.timeout_error?(nil)
    refute ClickhouseRepo.timeout_error?(:some_atom)
  end
end
