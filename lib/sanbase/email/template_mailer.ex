defmodule Sanbase.TemplateMailer do
  use Swoosh.Mailer, otp_app: :sanbase

  require Logger

  import Swoosh.Email

  @sender_email "support@santiment.net"
  @sender_name "Santiment"
  @post_sign_up_from {"Maksim from Santiment", "maksim.t@santiment.net"}
  @post_cancellation_email_from {"Santiment Team", "feedback@santiment.net"}

  def send(rcpt_email, template_slug, vars) when is_binary(rcpt_email) and rcpt_email != "" do
    template = Sanbase.Email.Template.templates()[template_slug]
    vars = Map.put(vars, :current_year, Date.utc_today().year)
    from = generate_from(template_slug)

    if template do
      subject =
        case template[:dynamic_subject] do
          subject when is_binary(subject) -> Sanbase.TemplateEngine.run!(subject, params: vars)
          nil -> template[:subject]
        end

      new()
      |> to(rcpt_email)
      |> from(from)
      |> subject(subject)
      |> put_provider_option(:template_id, template[:id])
      |> put_provider_option(:template_error_deliver, false)
      |> put_provider_option(:template_error_reporting, "team.backend@santiment.net")
      |> put_provider_option(:variables, vars)
      |> deliver()
    else
      Logger.error("Missing email template: #{template_slug}")
      {:error, "Could not send email: Missing template."}
    end
  end

  def send(_, _template_slug, _vars) do
    {:error, "invalid email"}
  end

  def generate_from(template_slug) do
    case template_slug do
      "sanbase-post-registration-mail" -> @post_sign_up_from
      "post-cancellation-email2" -> @post_cancellation_email_from
      _ -> {@sender_name, @sender_email}
    end
  end
end
