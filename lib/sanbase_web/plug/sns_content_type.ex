defmodule SanbaseWeb.Plug.SnsContentType do
  @moduledoc ~s"""
  Normalize the Content-Type of AWS SNS requests so that Plug.Parsers can parse them.

  AWS SNS delivers HTTP/S notifications (SubscriptionConfirmation, Notification,
  UnsubscribeConfirmation) with `Content-Type: text/plain; charset=UTF-8`, even though
  the body is JSON. Our Plug.Parsers only parses urlencoded/multipart/json and is
  configured with `pass: ["*/*"]`, which means text/plain bodies are passed through
  WITHOUT being parsed. The webhook controller would then receive only the path params
  and silently drop the event (see SanbaseWeb.SESController).

  This plug detects SNS requests via the `x-amz-sns-message-type` header (always set by
  SNS) and rewrites the Content-Type to `application/json` so the JSON parser kicks in.

  This plug must be placed before Plug.Parsers. It only touches request headers, so it
  is safe to run before the body is read.
  """
  @behaviour Plug

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "x-amz-sns-message-type") do
      [_ | _] ->
        conn
        |> delete_req_header("content-type")
        |> put_req_header("content-type", "application/json")

      _ ->
        conn
    end
  end
end
