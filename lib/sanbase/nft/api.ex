defmodule Sanbase.NFT.Api do
  require Sanbase.Utils.Config, as: Config
  require Logger

  @base_url "https://deep-index.moralis.io/api/v2/"
  @ipfs_gateway "https://cf-ipfs.com/ipfs/"

  def list_all_nfts(address, offset, limit) do
    request_path =
      Path.join(address, "nft") <>
        "/?" <>
        URI.encode_query(%{
          "chain" => "eth",
          "format" => "decimal",
          "limit" => limit,
          "offset" => offset
        })

    Path.join(@base_url, request_path)
    |> http_client().get(headers())
    |> handle_response()
    |> case do
      {:ok, data} -> Map.take(data, ~w(page page_size total result))
    end
  end

  def fetch_nft_details(contract, token_id) do
    request_path =
      Path.join(["nft", contract, to_string(token_id)]) <>
        "?" <> URI.encode_query(%{"chain" => "eth", "format" => "decimal"})

    Path.join(@base_url, request_path)
    |> http_client().get(headers())
    |> handle_response()
    |> case do
      {:ok, data} ->
        case fetch_image_url(data) do
          {:ok, image_url} -> Map.put(data, "image_url", image_url)
          _ -> data
        end
        |> Map.take(~w(name symbol token_address token_id synced_at contract_type image_url))

      error ->
        error
    end
  end

  def fetch_nft_avatar(contract, token_id) do
    fetch_nft_details(contract, token_id)
    |> extract_image()
  end

  # private
  defp handle_response(response) do
    response
    |> case do
      {:ok, %HTTPoison.Response{status_code: code, body: body}} when code in 200..299 ->
        {:ok, body |> Jason.decode!()}

      other ->
        Logger.warn("Error response from Moralis API: #{inspect(filter_response(other))}")
        {:error, "Error response from API"}
    end
  end

  defp fetch_image_url(%{"metadata" => metadata_json}) do
    with {:ok, metadata} <- Jason.decode(metadata_json),
         {:ok, image_url} <- Map.fetch(metadata, "image") do
      convert_to_http_url(image_url)
    end
  end

  defp convert_to_http_url(url) do
    cond do
      String.starts_with?(url, "ipfs://") ->
        {:ok, @ipfs_gateway <> String.trim_leading(url, "ipfs://")}

      String.starts_with?(url, "https://") ->
        {:ok, url}

      true ->
        {:error, "Invalid image url"}
    end
  end

  defp extract_image(%{"image_url" => image_url} = nft) when not is_nil(image_url) do
    with {:ok, image_url} <- convert_to_http_url(image_url) do
      do_fetch_image(image_url, nft)
    end
  end

  defp extract_image(_), do: {:error, :enoimage}

  def do_fetch_image(image_url, nft) do
    http_client().get(image_url)
    |> handle_response_with_redirect(nft)
  end

  def handle_response_with_redirect(response, nft) do
    response
    |> case do
      {:ok, %HTTPoison.Response{status_code: code, body: body}} when code in 200..299 ->
        {:ok, %{body: body, metadata: nft}}

      {:ok, %HTTPoison.Response{status_code: code, headers: headers}} when code in [301] ->
        headers = Enum.into(headers, %{})
        url = headers["Location"]

        nft =
          nft
          |> Map.put("content-type", headers["Content-Type"])
          |> Map.put("content-length", headers["Content-Length"])

        do_fetch_image(url, nft)

      other ->
        Logger.warn("Error response from downloading image: #{inspect(filter_response(other))}")
        {:error, "Error response from downloading image"}
    end
  end

  defp filter_response(
         {:ok, %HTTPoison.Response{request: %HTTPoison.Request{headers: _}} = response}
       ) do
    response
    |> Map.put(:request, Map.put(Map.from_struct(response.request), :headers, "***filtered***"))
  end

  defp filter_response(other), do: other

  defp http_client(), do: HTTPoison

  defp headers() do
    [
      {"Content-Type", "application/json"},
      {"X-API-Key", "#{Config.get(:api_key)}"}
    ]
  end
end
