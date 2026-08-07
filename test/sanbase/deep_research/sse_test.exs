defmodule Sanbase.DeepResearch.SSETest do
  use ExUnit.Case, async: true

  alias Sanbase.DeepResearch.SSE

  describe "feed/2" do
    test "returns complete lines and keeps the partial tail buffered" do
      assert {["event: a", "data: 1"], "data: par"} = SSE.feed("", "event: a\ndata: 1\ndata: par")
    end

    test "emits nothing while no newline has arrived" do
      assert {[], "data: {\"a\""} = SSE.feed("", "data: {\"a\"")
    end

    test "joins a line split across chunk boundaries" do
      # A single `data:` line arriving in three pieces must surface exactly once,
      # whole — this is the framing bug the module exists to prevent.
      {lines1, buf1} = SSE.feed("", "data: {\"ty")
      {lines2, buf2} = SSE.feed(buf1, "pe\": \"chart")
      {lines3, buf3} = SSE.feed(buf2, "\"}\n")

      assert lines1 == []
      assert lines2 == []
      assert lines3 == ["data: {\"type\": \"chart\"}"]
      assert buf3 == ""
    end

    test "a chunk ending exactly on a newline leaves an empty buffer" do
      assert {["data: 1"], ""} = SSE.feed("", "data: 1\n")
    end

    test "blank separator lines are emitted as empty strings, not swallowed" do
      assert {["data: 1", "", "data: 2"], ""} = SSE.feed("", "data: 1\n\ndata: 2\n")
    end

    test "many events in one chunk all come out, in order" do
      chunk = "data: 1\n\ndata: 2\n\ndata: 3\n\n"
      {lines, ""} = SSE.feed("", chunk)
      assert Enum.filter(lines, &(&1 != "")) == ["data: 1", "data: 2", "data: 3"]
    end
  end

  describe "flush/1" do
    test "an empty buffer yields nothing" do
      assert {[], ""} = SSE.flush("")
    end

    test "a final line with no trailing newline is still delivered" do
      # Servers may close the stream without a terminating newline; the last
      # event must not be dropped.
      assert {["data: {\"ok\": true}"], ""} = SSE.flush("data: {\"ok\": true}")
    end
  end

  test "feed/2 then flush/1 reconstructs every line of a stream, however chunked" do
    stream = "event: metadata\ndata: {\"run_id\": \"r1\"}\n\nevent: custom\ndata: {\"n\": 2}"

    for size <- [1, 3, 7, 13, 500] do
      {lines, buffer} =
        stream
        |> chunk_every(size)
        |> Enum.reduce({[], ""}, fn chunk, {acc, buf} ->
          {new, buf} = SSE.feed(buf, chunk)
          {acc ++ new, buf}
        end)

      {tail, ""} = SSE.flush(buffer)

      assert Enum.filter(lines ++ tail, &(&1 != "")) == [
               "event: metadata",
               "data: {\"run_id\": \"r1\"}",
               "event: custom",
               "data: {\"n\": 2}"
             ],
             "framing broke at chunk size #{size}"
    end
  end

  defp chunk_every(binary, size) do
    binary |> String.graphemes() |> Enum.chunk_every(size) |> Enum.map(&Enum.join/1)
  end
end
