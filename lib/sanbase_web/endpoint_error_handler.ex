defmodule SanbaseWeb.Endpoint.ErrorHandler do
  @moduledoc ~s"""
  Handle errors that happened in the Endpoint.

  This will specifically handle:
  1. Anything that has either :status_code or :plug_status field such as:
    - Plug Parser Error - HTTP Status Code 400
    - Phoenix Routing Error - HTTP Status Code 404
    - Any other Plug or Phoenix specific error
   2. Anything that does not have these fields will return HTTP Status Code 500

  If the error is catched here the GraphQL Layer has not been reached, so the
  `has_graphql_errors` field is set to `nil`. The GraphQL layer is responsible
  for parsing the query, authorization and extraction of SAN Balance, so these
  fields cannot be provided, too.
  """
  defmacro __using__(_opts) do
    quote do
      @before_compile unquote(__MODULE__)
    end
  end

  defmacro __before_compile__(_) do
    quote do
      defoverridable call: 2

      # Phoenix.Endpoint.call/2 function is defined in a before_compile hook
      # so in order to catch errors with it the `__using__` and `__before_compile__`
      # macros need to be redefined. Using `super(conn, opts)` calls the original
      # call function that was to be executed and wraps it in a try-rescue block
      def call(conn, opts) do
        try do
          super(conn, opts)
        catch
          kind, reason ->
            export_api_call_data(conn, kind, reason)
            :erlang.raise(kind, reason, __STACKTRACE__)
        end
      end

      defp export_api_call_data(conn, kind, reason) do
        remote_ip = conn.remote_ip |> Sanbase.Utils.IP.ip_tuple_to_string()
        status_code = get_status_code(reason)
        user_agent = Plug.Conn.get_req_header(conn, "user-agent") |> List.first()

        api_call_map(status_code, remote_ip, user_agent)
        |> Sanbase.Kafka.ApiCall.json_kv_tuple()
        |> Sanbase.KafkaExporter.persist_async(:api_call_exporter)
      end

      defp get_status_code(reason) do
        case reason do
          %{} -> Map.get(reason, :status_code) || Map.get(reason, :plug_status, 500)
          _ -> 500
        end
      end

      defp api_call_map(status_code, remote_ip, user_agent) do
        id =
          Logger.metadata() |> Keyword.get(:request_id) ||
            "gen_" <> (:crypto.strong_rand_bytes(16) |> Base.encode64())

        %{
          timestamp: DateTime.utc_now() |> DateTime.to_unix(),
          id: id,
          query: nil,
          status_code: status_code,
          has_graphql_errors: nil,
          user_id: nil,
          auth_method: nil,
          api_token: nil,
          remote_ip: remote_ip,
          user_agent: user_agent,
          duration_ms: nil,
          san_tokens: nil
        }
      end
    end
  end
end
