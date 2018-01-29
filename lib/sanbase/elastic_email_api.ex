defmodule Sanbase.ElasticEmail do
  alias Sanbase.Utils.Config

  @send_email_url "https://api.elasticemail.com/v2/email/send"

  def send(template, parameters) do
    options = login_credentials() ++ parameters

    case HTTPoison.post(@send_email_url, {:form, options}) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, Poison.decode(body)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp login_credentials() do
    [
      {:apikey, Config.module_get(__MODULE__, :apikey)},
      {:from, Config.module_get(__MODULE__, :from_email)}
    ]
  end
end
