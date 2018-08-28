defmodule PlugAttackTest do
  use SanbaseWeb.ConnCase, async: false

  setup do
    :ets.delete_all_objects(:"Elixir.SanbaseWeb.Graphql.PlugAttack.Storage")
    :ok
  end

  test "get graphql updates the remaining ratelimit headers", %{conn: conn} do
    conn = %{conn | remote_ip: {192, 168, 0, 1}}
    response = conn |> get("/graphql")

    ratelimit_remaining =
      response
      |> get_resp_header("x-ratelimit-remaining")
      |> List.first()

    assert ratelimit_remaining == Integer.to_string(get_max_requests() - 1)
  end

  test "after max requests the api returns 403 Forbidden", %{conn: conn} do
    conn = %{conn | remote_ip: {192, 168, 0, 1}}

    for _n <- 1..get_max_requests(), do: conn |> get("/graphql")

    response = conn |> get("/graphql")

    assert response.status == 403
  end

  defp get_max_requests() do
    require Sanbase.Utils.Config, as: Config

    Config.module_get(SanbaseWeb.Graphql.PlugAttack, :rate_limit_max_requests)
    |> String.to_integer()
  end
end
