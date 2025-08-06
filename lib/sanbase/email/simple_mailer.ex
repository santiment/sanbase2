defmodule Sanbase.SimpleMailer do
  use Swoosh.Mailer, otp_app: :sanbase

  require Logger

  import Swoosh.Email

  def send_email(rcpt_email, subject, body) do
    if Sanbase.Email.email_excluded?(rcpt_email) do
      Logger.info("Email #{rcpt_email} is excluded from receiving emails")
      {:ok, :excluded}
    else
      new()
      |> from({"Santiment", "support@santiment.net"})
      |> to(rcpt_email)
      |> subject(subject)
      |> text_body(body)
      |> deliver()
    end
  end
end
