defmodule Sanbase.MandrillApi do
  alias Sanbase.Utils.Config
  require Sanbase.Utils.Config

  @send_email_url "https://mandrillapp.com/api/1.0/messages/send.json"

  def send(template, recepient, variables) do
    request_body =
      build_request(template, recepient, variables)
      |> Poison.encode!()
      |> IO.inspect()

    case HTTPoison.post(@send_email_url, request_body) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, Poison.decode!(body)}

      {:ok, %HTTPoison.Response{body: body}} ->
        {:error, Poison.decode!(body)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp build_request(template, recepient, variables) do
    %{
      template_name: template,
      message: %{
        to: [
          %{
            email: recepient
          }
        ],
        global_merge_vars: build_global_merge_vars(variables)
      },
      key: Config.module_get(__MODULE__, :apikey),
      from_email: Config.module_get(__MODULE__, :from_email)
    }
  end

  defp build_global_merge_vars(variables) do
    variables
    |> Enum.map(fn {key, value} ->
      %{name: key, content: value}
    end)
  end
end
