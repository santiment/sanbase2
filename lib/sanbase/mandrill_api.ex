defmodule Sanbase.MandrillApi do
  require Sanbase.Utils.Config, as: Config

  @send_email_url "https://mandrillapp.com/api/1.0/messages/send-template.json"
  @environment Mix.env()

  def send(template, recepient, variables) do
    request_body =
      build_request(template, recepient, variables)
      |> Jason.encode!()

    case HTTPoison.post(@send_email_url, request_body) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %HTTPoison.Response{body: body}} ->
        {:error, Jason.decode!(body)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp build_request(template, recepient, variables) do
    %{
      template_name: template,
      template_content: [],
      message: %{
        to: [
          %{
            email: recepient
          }
        ],
        global_merge_vars: build_global_merge_vars(variables),
        from_email: Config.get(:from_email),
        from_name: "Santiment Sanbase"
      },
      tags: [@environment, template],
      key: Config.get(:apikey)
    }
  end

  defp build_global_merge_vars(variables) do
    variables
    |> Enum.map(fn {key, value} ->
      %{name: key, content: value}
    end)
  end
end
