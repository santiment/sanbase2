defmodule Sanbase.SimpleMailer do
  use Swoosh.Mailer, otp_app: :sanbase

  require Logger

  import Swoosh.Email

  def send_email(rcpt_email, subject, body) do
    cond do
      not valid_rcpt_email?(rcpt_email) ->
        Logger.warning("Not sending email to the malformed address #{inspect(rcpt_email)}")
        {:error, :invalid_email}

      Sanbase.Email.email_excluded?(rcpt_email) ->
        Logger.info("Email #{rcpt_email} is excluded from receiving emails")
        {:ok, :excluded}

      true ->
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

  # gen_smtp's RFC 5322 parser is what the MIME encoding uses for the "To" header, so an
  # address it cannot parse makes the delivery crash with a MatchError.
  defp valid_rcpt_email?(rcpt_email) when is_binary(rcpt_email) do
    match?({:ok, [_]}, :smtp_util.parse_rfc5322_addresses(rcpt_email))
  end

  defp valid_rcpt_email?(_), do: false

  # Building the raw message can still raise or exit for addresses that parse but cannot
  # be encoded (e.g. a domain label that is not valid IDNA).
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
