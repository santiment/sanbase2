defmodule Sanbase.Auth.Ethauth do
  use Tesla

  import Sanbase.Utils, only: [parse_config_value: 1]

  def verify_signature(signature, address, address_hash) do
    %Tesla.Env{status: 200, body: body} = get(client(), "auth-check", query: [addr: address, sign: signature, hash: address_hash])

    %{"addr" => address, "recovered" => recovered} = Poison.decode!(body)

    String.downcase(address) == String.downcase(recovered)
  end

  def san_balance(address) do
    %Tesla.Env{status: 200, body: body} = get(client(), "san-balance", query: [addr: address])

    body
    |> String.to_integer()
    |> Kernel.div(100000000)
  end

  defp client() do
    ethauth_url = config(:url)
    basic_auth_username = config(:basic_auth_username)
    basic_auth_password = config(:basic_auth_password)

    Tesla.build_client [
      {Tesla.Middleware.BaseUrl, ethauth_url},
      {Tesla.Middleware.BasicAuth, username: basic_auth_username, password: basic_auth_password},
      Tesla.Middleware.Logger
    ]
  end

  defp config(key) do
    Application.get_env(:sanbase, __MODULE__)
    |> Keyword.get(key)
    |> parse_config_value()
  end
end
