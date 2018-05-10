defmodule Sanbase.InternalServices.Ethauth do
  use Tesla

  require Sanbase.Utils.Config
  alias Sanbase.Utils.Config

  @san_token_decimals Decimal.new(:math.pow(10, 18))

  def verify_signature(signature, address, message_hash) do
    %Tesla.Env{status: 200, body: body} =
      get(client(), "recover", query: [sign: signature, hash: message_hash])

    %{"recovered" => recovered} = Poison.decode!(body)

    String.downcase(address) == String.downcase(recovered)
  end

  def san_balance(address) do
    %Tesla.Env{status: 200, body: body} = get(client(), "san_balance", query: [addr: address])

    body
    |> Decimal.new()
    |> Decimal.div(@san_token_decimals)
  end

  def san_token_decimals() do
    @san_token_decimals
  end

  defp client() do
    ethauth_url = Config.get(:url)
    basic_auth_username = Config.get(:basic_auth_username)
    basic_auth_password = Config.get(:basic_auth_password)

    Tesla.build_client([
      {Tesla.Middleware.BaseUrl, ethauth_url},
      {Tesla.Middleware.BasicAuth, username: basic_auth_username, password: basic_auth_password},
      Tesla.Middleware.Logger
    ])
  end
end
