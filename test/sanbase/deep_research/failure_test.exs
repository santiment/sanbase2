defmodule Sanbase.DeepResearch.FailureTest do
  use ExUnit.Case, async: true

  alias Sanbase.DeepResearch.Failure

  @url "http://127.0.0.1:2024"

  defp transport(reason), do: %Req.TransportError{reason: reason}

  describe "connection/3" do
    test "names the call, the agent and what the reason means" do
      failure = Failure.connection("create_thread", @url, transport(:timeout))

      assert failure.resumable?
      assert failure.message =~ "the request timed out"
      assert failure.message =~ "create_thread"
      assert failure.message =~ @url
    end

    test "translates the transport reasons that read as nothing on their own" do
      for {reason, text} <- [
            econnrefused: "nothing is listening",
            closed: "closed mid-request",
            econnreset: "was reset",
            nxdomain: "could not be resolved",
            ehostunreach: "unreachable from this network",
            enetunreach: "unreachable from this network"
          ] do
        assert Failure.connection("get_state", @url, transport(reason)).message =~ text
      end
    end

    test "an unrecognized error still carries its own message" do
      error = %Req.HTTPError{protocol: :http2, reason: :unprocessed}

      assert Failure.connection("the research stream", @url, error).message =~
               Exception.message(error)
    end
  end

  describe "response/3" do
    test "an answer from the agent is not resumable — retrying gets the same answer" do
      refute Failure.response("create_thread", 500, "boom").resumable?
    end

    test "the statuses with a known cause say what to look at" do
      assert Failure.response("create_thread", 401, nil).message =~ "DRA_AUTH_TOKEN"
      assert Failure.response("create_thread", 403, nil).message =~ "DRA_AUTH_TOKEN"
      assert Failure.response("get_state", 404, nil).message =~ "no such thread"
      assert Failure.response("The run", 502, nil).message =~ "the agent itself errored"
    end

    test "the body is carried along, trimmed — an agent stack trace would swamp the UI" do
      failure = Failure.response("The run", 500, String.duplicate("stack trace ", 200))

      assert failure.message =~ "stack trace"
      assert String.length(failure.message) < 400
    end

    test "an empty body leaves no dangling punctuation" do
      assert Failure.response("cancel_run", 409, "").message == "cancel_run failed (HTTP 409)."
    end
  end

  test "crashed/1 is resumable — our side stopped, the agent kept the thread" do
    failure = Failure.crashed(:killed)

    assert failure.resumable?
    assert failure.message =~ ":killed"
  end

  test "refused/1 is not resumable — a human has to change the configuration" do
    refute Failure.refused("base_url is plain HTTP").resumable?
  end
end
