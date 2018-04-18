defmodule Sanbase.Utils.JsonLogger do
  def format(level, message, {date, {h, min, s, ms}} = timestamp, metadata) do
    [
      %{
        timestamp: NaiveDateTime.from_erl!({date, {h, min, s}}, {ms * 1000, 3}),
        level: level,
        message: "#{message}"
      }
      |> Poison.encode_to_iodata!()
      | "\n"
    ]
  rescue
    error ->
      "Could not format log message as json: #{inspect({level, timestamp, message, metadata})}. Reason: #{
        inspect(error)
      }.\n"
  end
end
