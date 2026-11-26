defmodule SanbaseWeb.Plug.RedactedLogger do
  @moduledoc ~s"""
  Drop-in replacement for `Plug.Logger` that does not write secrets to the logs.

  Some routes carry a static secret in the URL path (`/telegram/:path`,
  `/bot/login/:path/:user`, `/mailjet/webhook/:secret`, ...). `Plug.Logger` logs
  the whole request path, so those secrets ended up in the application logs.
  This plug logs the same lines (`GET /path` and `Sent 200 in 5ms`) but replaces
  the secret path segments with `[REDACTED]`.

  The routes themselves are unchanged, so external callers are not affected.
  Only `conn.request_path` is logged, the query string never is.
  """

  @behaviour Plug

  require Logger

  @redacted "[REDACTED]"

  # Routes of the form /<prefix>/<secret>
  @secret_after_one ~w(
    telegram
    monitored_twitter_handles
    santiment_team_members
    projects_data_validator_webhook
    projects_data_reader_webhook
  )

  # Routes of the form /<prefix>/<second>/<secret>
  @secret_after_two [["mailjet", "webhook"], ["ses", "webhook"]]

  @impl true
  def init(opts), do: Keyword.get(opts, :log, :info)

  @impl true
  def call(conn, level) do
    Logger.log(level, fn -> [conn.method, ?\s, redact_path(conn.request_path)] end)

    start = System.monotonic_time()

    Plug.Conn.register_before_send(conn, fn conn ->
      Logger.log(level, fn ->
        diff = System.convert_time_unit(System.monotonic_time() - start, :native, :microsecond)

        [
          connection_type(conn),
          ?\s,
          Integer.to_string(conn.status),
          " in ",
          formatted_diff(diff)
        ]
      end)

      conn
    end)
  end

  @doc false
  def redact_path(path) when is_binary(path) do
    segments = String.split(path, "/")

    redacted =
      case segments do
        ["", "bot", "login" | rest] when rest != [] ->
          ["", "bot", "login"] ++ Enum.map(rest, fn _ -> @redacted end)

        ["", prefix, _secret | tail] when prefix in @secret_after_one ->
          ["", prefix, @redacted | tail]

        ["", a, b, _secret | tail] ->
          if [a, b] in @secret_after_two, do: ["", a, b, @redacted | tail], else: segments

        _ ->
          segments
      end

    Enum.join(redacted, "/")
  end

  defp formatted_diff(diff) when diff > 1000,
    do: [diff |> div(1000) |> Integer.to_string(), "ms"]

  defp formatted_diff(diff), do: [Integer.to_string(diff), "µs"]

  defp connection_type(%{state: :set_chunked}), do: "Chunked"
  defp connection_type(_), do: "Sent"
end
