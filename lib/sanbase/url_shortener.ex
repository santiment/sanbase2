defmodule Sanbase.UrlShortener do
  require Logger

  def short_url(url) do
    post(url)
    |> case do
      {:ok, %HTTPoison.Response{status_code: code, body: body}} when code in 200..299 ->
        short_url =
          body
          |> Floki.find("div#copyinfo")
          |> Floki.attribute("data-clipboard-text")
          |> hd

        {:ok, short_url}

      error ->
        Logger.error("Cannot shorten url: " <> inspect(error))
        {:error, "Cannot create short url"}
    end
  end

  defp post(url) do
    HTTPoison.post(
      "https://tinyurl.com/create.php",
      URI.encode_query(%{"url" => url}),
      %{"Content-Type" => "application/x-www-form-urlencoded"}
    )
  end
end
