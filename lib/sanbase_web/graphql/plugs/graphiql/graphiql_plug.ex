defmodule SanbaseWeb.Graphql.GraphiqlPlug do
  @moduledoc """
  Serves the Santiment GraphiQL interface (GraphiQL 5 with Monaco Editor).

  The interface is fully client-side — the plug only renders a static HTML shell
  that loads the bundled JavaScript and CSS assets. All query execution, headers,
  variables, and URL parameter handling happen in the browser.

  ## Usage

      forward "/graphiql",
        SanbaseWeb.Graphql.GraphiqlPlug,
        schema: SanbaseWeb.Graphql.Schema,
        interface: :santiment,
        # ... other Absinthe.Plug options
  """

  require EEx
  import Phoenix.Controller, only: [put_secure_browser_headers: 2]

  @graphiql_template_path Path.join(__DIR__, "templates")

  @graphiql_csp "default-src 'self'; " <>
                  "script-src 'self'; " <>
                  "style-src 'self' 'unsafe-inline'; " <>
                  "font-src 'self' data:; " <>
                  "img-src 'self' data:; " <>
                  "connect-src 'self'; " <>
                  "worker-src 'self' blob:; " <>
                  "frame-ancestors 'self'"

  EEx.function_from_file(
    :defp,
    :graphiql_santiment_html,
    Path.join(@graphiql_template_path, "graphiql_santiment.html.eex"),
    []
  )

  @behaviour Plug

  import Plug.Conn

  @doc false
  def init(opts) do
    opts
    |> Absinthe.Plug.init()
    |> Map.put(:interface, :santiment)
    |> set_pipeline()
  end

  @doc false
  def call(conn, config) do
    case html?(conn) do
      true ->
        graphiql_santiment_html()
        |> rendered(conn)

      _ ->
        Absinthe.Plug.call(conn, config)
    end
  end

  defp html?(conn) do
    Plug.Conn.get_req_header(conn, "accept")
    |> List.first()
    |> case do
      string when is_binary(string) ->
        String.contains?(string, "text/html")

      _ ->
        false
    end
  end

  defp set_pipeline(config) do
    config
    |> Map.put(:additional_pipeline, config.pipeline)
    |> Map.put(:pipeline, {__MODULE__, :pipeline})
  end

  @doc false
  def pipeline(config, opts) do
    {module, fun} = config.additional_pipeline

    apply(module, fun, [config, opts])
    |> Absinthe.Pipeline.insert_after(
      Absinthe.Phase.Document.CurrentOperation,
      [
        Absinthe.GraphiQL.Validation.NoSubscriptionOnHTTP
      ]
    )
  end

  @spec rendered(String.t(), Plug.Conn.t()) :: Plug.Conn.t()
  defp rendered(html, conn) do
    conn
    |> put_secure_browser_headers(%{
      "content-security-policy" => @graphiql_csp,
      "strict-transport-security" => "max-age=31536000; includeSubDomains"
    })
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end
end
