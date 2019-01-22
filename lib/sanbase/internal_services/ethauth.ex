defmodule Sanbase.InternalServices.Ethauth do
  use Tesla
  require Sanbase.Utils.Config, as: Config

  @san_token_decimals Decimal.from_float(:math.pow(10, 18))
  def san_token_decimals(), do: @san_token_decimals

  def verify_signature(signature, address, message_hash) do
    with {:ok, %Tesla.Env{status: 200, body: body}} <-
           get(client(), "recover",
             query: [sign: signature, hash: message_hash],
             opts: [adapter: [recv_timeout: 15_000]]
           ),
         {:ok, %{"recovered" => recovered}} <- Jason.decode(body) do
      String.downcase(address) == String.downcase(recovered)
    else
      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error,
         "Error veryfing signature for address. #{address}. Status: #{status}. Body: #{
           inspect(body)
         }"}

      {:error, error} ->
        {:error, "Error veryfing signature for address. #{address}. Reason: #{inspect(error)}"}

      error ->
        {:error, "Error veryfing signature for address. #{address}. Reason: #{inspect(error)}"}
    end
  end

  def san_balance(address) do
    get(client(), "san_balance", query: [addr: address], opts: [adapter: [recv_timeout: 15_000]])
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        san_balance =
          body
          |> Decimal.new()
          |> Decimal.div(@san_token_decimals)

        {:ok, san_balance}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error,
         "Error fetching SAN balance for address. #{address}. Status: #{status}. Body: #{
           inspect(body)
         }"}

      {:error, error} ->
        {:error, "Error fetching SAN balance for address. #{address}. Reason: #{inspect(error)}"}
    end
  end

  defp client() do
    ethauth_url = Config.get(:url)

    Tesla.client([
      Sanbase.ExternalServices.ErrorCatcher.Middleware,
      {Tesla.Middleware.BaseUrl, ethauth_url},
      Tesla.Middleware.Logger
    ])
  end
end
