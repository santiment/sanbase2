defmodule Sanbase.Utils.JsonLogger do
  @moduledoc false
  def format(level, message, timestamp, metadata) do
    {date, {h, min, s, ms}} = timestamp

    [
      %{
        timestamp: NaiveDateTime.from_erl!({date, {h, min, s}}, {ms * 1000, 3}),
        level: level,
        message: "#{message}"
      }
      |> Map.merge(Map.new(metadata))
      |> Jason.encode_to_iodata!()
      | "\n"
    ]
  rescue
    error ->
      "Could not format log message as json: #{inspect({level, timestamp, message, metadata})}. Reason: #{inspect(error)}.\n"
  end
end
