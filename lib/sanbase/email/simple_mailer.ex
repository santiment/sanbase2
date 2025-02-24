defmodule Sanbase.SimpleMailer do
  use Swoosh.Mailer, otp_app: :sanbase

  import Swoosh.Email

  def send_email(rcpt_email, subject, body) do
    new()
    |> from("support@santiment.net")
    |> to(rcpt_email)
    |> subject(subject)
    |> text_body(body)
    |> deliver()
  end
end
