defmodule Sanbase.SocialData.MetricsHubClient do
  @moduledoc """
  JSON POSTs to metrics-hub's generic `/<function>` route, which answers
  `{"data": ...}` on success and `{"error": ..., "trace": ...}` on failure.

  Errors come back as `{kind, message}`:
    * `:transient` - metrics-hub is unreachable, timed out or answered 502/503/504 (a
      gateway or a restarting pod).
    * `:unknown` - metrics-hub returned an error. Its route answers 400 for every exception,
      bad arguments and Elasticsearch outages alike, and 500 from its catch-all handler
      (e.g. a function this metrics-hub version does not have), so the status says nothing
      about whether a retry can succeed.
  """

  require Logger

  alias Sanbase.Utils.Config

  @timeout 60_000

  @type error :: {:transient | :unknown, String.t()}

  @doc "POST `body` as JSON to `path` (e.g. `/sample_documents`) and return its `data`."
  @spec post(String.t(), map()) :: {:ok, term()} | {:error, error()}
  def post(path, body) when is_binary(path) and is_map(body) do
    url = metrics_hub_url() <> path

    case Req.post(url, json: body, receive_timeout: @timeout, retry: false) do
      {:ok, %Req.Response{status: 200, body: response_body}} ->
        parse_body(response_body)

      {:ok, %Req.Response{status: status, body: response_body}} when status in [502, 503, 504] ->
        {:error,
         {:transient, "metrics-hub returned HTTP #{status}: #{error_detail(response_body)}"}}

      {:ok, %Req.Response{status: status, body: response_body}} ->
        {:error,
         {:unknown, "metrics-hub returned HTTP #{status}: #{error_detail(response_body)}"}}

      {:error, exception} ->
        Logger.warning("[MetricsHubClient] POST #{path} failed: #{inspect(exception)}")
        {:error, {:transient, "metrics-hub is unreachable: #{Exception.message(exception)}"}}
    end
  end

  @doc "An error for a `data` value whose shape the caller does not expect."
  @spec unexpected(term()) :: {:error, error()}
  def unexpected(data),
    do: {:error, {:transient, "Unexpected metrics-hub response: #{truncate(data)}"}}

  defp parse_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> parse_body(decoded)
      _ -> unexpected(body)
    end
  end

  defp parse_body(%{"error" => error}) when not is_nil(error),
    do: {:error, {:unknown, "metrics-hub error: #{truncate(error)}"}}

  # Some metrics-hub functions return their data as a JSON string.
  defp parse_body(%{"data" => data}) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:ok, data}
    end
  end

  defp parse_body(%{"data" => data}), do: {:ok, data}
  defp parse_body(body), do: unexpected(body)

  defp error_detail(%{"error" => error}) when not is_nil(error), do: truncate(error)
  defp error_detail(%{"message" => message}) when not is_nil(message), do: truncate(message)
  defp error_detail(body), do: truncate(body)

  defp truncate(value) when is_binary(value), do: String.slice(value, 0, 300)
  defp truncate(value), do: value |> inspect() |> String.slice(0, 300)

  defp metrics_hub_url() do
    Config.module_get(Sanbase.SocialData, :metricshub_url) |> String.trim_trailing("/")
  end
end
