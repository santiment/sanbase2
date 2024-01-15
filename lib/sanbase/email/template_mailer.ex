defmodule Sanbase.TemplateMailer do
  use Swoosh.Mailer, otp_app: :sanbase

  require Logger

  import Swoosh.Email

  @sender_email "support@santiment.net"
  @sender_name "Santiment"

  def send(rcpt_email, template_slug, vars) do
    template = Sanbase.Email.Template.templates()[template_slug]
    vars = Map.put(vars, :current_year, Date.utc_today().year())

    if template do
      subject =
        case template[:dynamic_subject] do
          subject when is_binary(subject) -> Sanbase.TemplateEngine.run!(subject, params: vars)
          nil -> template[:subject]
        end

      new()
      |> to(rcpt_email)
      |> from({@sender_name, @sender_email})
      |> subject(subject)
      |> put_provider_option(:template_id, template[:id])
      |> put_provider_option(:template_error_deliver, false)
      |> put_provider_option(:template_error_reporting, "tsvetozar.p@santiment.net")
      |> put_provider_option(:variables, vars)
      |> deliver()
    else
      Logger.info("Missing email template: #{template_slug}")
      :ok
    end
  end
end
