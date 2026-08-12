defmodule SanbaseWeb.WellKnownControllerTest do
  use SanbaseWeb.ConnCase, async: true

  test "GET /.well-known/glama.json returns the Glama ownership proof", %{conn: conn} do
    response =
      conn
      |> get("/.well-known/glama.json")
      |> json_response(200)

    assert response == %{
             "$schema" => "https://glama.ai/mcp/schemas/connector.json",
             "maintainers" => [%{"email" => "team@santiment.net"}]
           }
  end
end
