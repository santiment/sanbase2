defmodule Sanbase.InternalServices.Ethauth do
  use Tesla
  require Sanbase.Utils.Config, as: Config

  @san_token_decimals Decimal.new(:math.pow(10, 18))
  def san_token_decimals(), do: @san_token_decimals

  def verify_signature(signature, address, message_hash) do
    with %Tesla.Env{status: 200, body: body} <-
           get(client(), "recover", query: [sign: signature, hash: message_hash]),
         {:ok, %{"recovered" => recovered}} <- Poison.decode!(body) do
      String.downcase(address) == String.downcase(recovered)
    else
      {:error, error} -> {:error, error}
      error -> {:error, error}
    end
  end

  def san_balance(address) do
    with %Tesla.Env{status: 200, body: body} <-
           get(client(), "san_balance", query: [addr: address]) do
      san_balance =
        body
        |> Decimal.new()
        |> Decimal.div(@san_token_decimals)

      {:ok, san_balance}
    else
      error -> {:error, error}
    end
  end

  defp client() do
    ethauth_url = Config.get(:url)

    Tesla.build_client([
      {Tesla.Middleware.Timeout, timeout: 30_000},
      Sanbase.ExternalServices.ErrorCatcher.Middleware,
      {Tesla.Middleware.BaseUrl, ethauth_url},
      Tesla.Middleware.Logger
    ])
  end
end
