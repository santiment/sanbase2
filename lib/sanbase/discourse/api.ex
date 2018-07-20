defmodule Sanbase.Discourse.Api do
  require Logger
  require Mockery.Macro

  alias Sanbase.Discourse.Config

  def publish(title, text, url \\ Config.discourse_url()) do
    url
    |> publish_topic(title, text)
    |> handle_response(title)
  end

  # Private functions

  defp handle_response(response, title) do
    case response do
      {:ok, %HTTPoison.Response{body: body, status_code: code}}
      when code >= 200 and code < 300 ->
        Logger.info("Successfully created a topic '#{title}' in Discourse")
        Poison.decode(body)

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        err_msg =
          "Error creating a topic '#{title}' in Discourse: HTTP status code: #{
            inspect(status_code)
          }."

        Logger.error(err_msg)
        {:error, err_msg}

      {:error, error} ->
        err_msg = "#Error creating a topic '#{title}' in Discourse: Error: #{inspect(error)}"

        Logger.error(err_msg)
        {:error, err_msg}
    end
  end

  defp publish_topic(url, title, text) do
    url = "#{url}/posts?api_key=#{Config.api_key()}"

    http_client().post(
      url,
      create_topic(%{
        title: title,
        raw: text
      })
    )
  end

  defp create_topic(%{
         title: title,
         raw: raw
       }) do
    {:form, [title: title, raw: raw, category: Config.category()]}
  end

  defp http_client(), do: Mockery.Macro.mockable(HTTPoison)
end
