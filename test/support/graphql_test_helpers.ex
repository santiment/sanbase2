defmodule SanbaseWeb.Graphql.TestHelpers do
  import Plug.Conn

  alias SanbaseWeb.Graphql.ContextPlug

  def query_skeleton(query, query_name, variable_defs \\ "", variables \\ "{}") do
    %{
      "operationName" => "#{query_name}",
      "query" => "query #{query_name}#{variable_defs} #{query}",
      "variables" => "#{variables}"
    }
  end

  def mutation_skeleton(query) do
    %{
      "operationName" => "",
      "query" => "#{query}",
      "variables" => ""
    }
  end

  def setup_jwt_auth(conn, user) do
    {:ok, token, _claims} = SanbaseWeb.Guardian.encode_and_sign(user, %{salt: user.salt})

    conn
    |> put_req_header("authorization", "Bearer " <> token)
    |> ContextPlug.call(%{})
  end

  def setup_apikey_auth(conn, apikey) do
    conn
    |> put_req_header("authorization", "Apikey " <> apikey)
    |> ContextPlug.call(%{})
  end

  def setup_basic_auth(conn, user, pass) do
    token = Base.encode64(user <> ":" <> pass)

    conn
    |> put_req_header("authorization", "Basic " <> token)
    |> ContextPlug.call(%{})
  end
end
