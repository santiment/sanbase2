defmodule Sanbase.DeepResearch.SSE do
  @moduledoc """
  Pure line framing for a Server-Sent Events byte stream.

  An SSE response arrives as arbitrarily chopped chunks: one chunk can hold
  several events, half an event, or split a single `data:` line down the middle.
  `feed/2` turns that byte soup into whole lines plus the leftover tail to carry
  into the next chunk, so no caller has to keep that state implicitly.

  The stream can also close without a trailing newline, leaving the final event
  in the buffer — hence `flush/1`, which yields whatever is left so a terminal
  `run_id` / `error` / `report` is never dropped.

      {lines, buffer} = SSE.feed("", "data: {\\"a\\":1}\\ndata: {\\"b\\"")
      #=> {["data: {\\"a\\":1}"], "data: {\\"b\\""}
      {lines, buffer} = SSE.feed(buffer, ":2}\\n")
      #=> {["data: {\\"b\\":2}"], ""}
  """

  @doc """
  Append `data` to `buffer` and split off every complete line.

  Returns `{complete_lines, remaining_buffer}`. The remaining buffer is the
  partial line after the last newline (`""` when the chunk ended cleanly).
  """
  @spec feed(String.t(), String.t()) :: {[String.t()], String.t()}
  def feed(buffer, data) when is_binary(buffer) and is_binary(data) do
    parts = String.split(buffer <> data, "\n")
    {complete, [rest]} = Enum.split(parts, -1)
    {complete, rest}
  end

  @doc """
  Drain a buffer left over when the stream closed without a trailing newline.

  Returns `{lines, ""}` — `lines` is empty when there was nothing buffered, so
  the result composes with `feed/2`.
  """
  @spec flush(String.t()) :: {[String.t()], String.t()}
  def flush(""), do: {[], ""}
  def flush(buffer) when is_binary(buffer), do: {[buffer], ""}
end
