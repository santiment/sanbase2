defmodule SanbaseWeb.Endpoint.ErrorHandler do
  @moduledoc ~s"""
  Handle errors that happened in the Endpoint.

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
      # so in order to catch errors with it the using and before compile macros
      # need to be used
      def call(conn, opts) do
        try do
          super(conn, opts)
        catch
          kind, reason ->
            export_api_call_data(conn, kind, reason)
            :erlang.raise(kind, reason, System.stacktrace())
        end
      end

      defp export_api_call_data(conn, kind, reason) do
        remote_ip = conn.remote_ip |> :inet_parse.ntoa() |> to_string
        status_code = Map.get(reason, :status_code, 500)

        user_agent =
          Enum.find(conn.req_headers, &match?({"user-agent", _}, &1))
          |> case do
            {"user-agent", user_agent} -> user_agent
            _ -> nil
          end

        %{
          timestamp: DateTime.utc_now() |> DateTime.to_unix(),
          query: nil,
          status_code: status_code,
          user_id: nil,
          auth_method: nil,
          api_token: nil,
          remote_ip: remote_ip,
          user_agent: user_agent,
          duration_ms: nil,
          san_tokens: nil
        }
        |> Sanbase.ApiCallDataExporter.persist()
      end
    end
  end
end
