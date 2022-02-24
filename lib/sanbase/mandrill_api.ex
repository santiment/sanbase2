defmodule Sanbase.MandrillApi do
  require Sanbase.Utils.Config, as: Config
  require Application

  @send_email_url "https://mandrillapp.com/api/1.0/messages/send-template.json"
  @environment Application.compile_env(:sanbase, :env)

  @spec send(any, String.t() | nil, any, map) :: {:error, any} | {:ok, any}
  def send(template, recepient, variables, message_opts \\ %{})

  def send(_template, nil, _variables, _message_opts), do: {:error, "No email address provided"}

  def send(template, recepient, variables, message_opts) do
    request_body =
      build_request(template, recepient, variables, message_opts)
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

  defp build_request(template, recepient, variables, message_opts) do
    message =
      Map.merge(
        %{
          to: [
            %{
              email: recepient
            }
          ],
          global_merge_vars: build_global_merge_vars(variables),
          from_email: Config.get(:from_email)
        },
        message_opts
      )

    %{
      template_name: template,
      template_content: [],
      message: message,
      tags: [@environment, template],
      key: Config.get(:apikey)
    }
  end

  defp build_global_merge_vars(variables) do
    variables =
      variables
      |> Enum.map(fn {key, value} -> %{name: key, content: value} end)

    variables ++ [%{name: "year", content: DateTime.utc_now().year}]
  end
end
