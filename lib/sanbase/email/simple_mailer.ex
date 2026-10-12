defmodule Sanbase.SimpleMailer do
  use Swoosh.Mailer, otp_app: :sanbase

  require Logger

  import Swoosh.Email

  def send_email(rcpt_email, subject, body) do
    if Sanbase.Email.email_excluded?(rcpt_email) do
      Logger.info("Email #{rcpt_email} is excluded from receiving emails")
      {:ok, :excluded}
    else
      email =
        new()
        |> from({"Santiment", "support@santiment.net"})
        |> to(rcpt_email)
        |> subject(subject)
        |> text_body(body)
        |> maybe_add_configuration_set()

      safe_deliver(email)
    end
  end

  # Encoding can still raise or exit (e.g. non-IDNA domain labels)
  defp safe_deliver(email) do
    deliver(email)
  rescue
    error ->
      Logger.error("Failed to deliver email: #{Exception.message(error)}")
      {:error, error}
  catch
    :exit, reason ->
      Logger.error("Failed to deliver email: #{inspect(reason)}")
      {:error, reason}
  end

  defp maybe_add_configuration_set(email) do
    case Application.get_env(:sanbase, Sanbase.SimpleMailer)[:configuration_set] do
      config_set when is_binary(config_set) and config_set != "" ->
        put_provider_option(email, :configuration_set_name, config_set)

      _ ->
        email
    end
  end
end
