defmodule Sanbase.TemplateMailer do
  use Swoosh.Mailer, otp_app: :sanbase

  require Logger

  import Swoosh.Email

  @sender_email "support@santiment.net"
  @sender_name "Santiment"
  @post_sign_up_from {"Maksim from Santiment", "maksim.t@santiment.net"}
  @post_cancellation_email_from {"Santiment Team", "feedback@santiment.net"}

  def send(rcpt_email, template_slug, vars)
      when is_binary(rcpt_email) and rcpt_email != "" and
             template_slug in [
               "sanbase-sign-in-mail",
               "neuro-sign-in",
               "sheets-sign-in",
               "sanbase-sign-up-mail",
               "neuro-sign-up",
               "sheets-sign-up",
               "sanbase-verify-email-mail"
             ] do
    template = Sanbase.Email.Template.templates()[template_slug]

    subject =
      case template[:dynamic_subject] do
        subject when is_binary(subject) -> Sanbase.TemplateEngine.run!(subject, params: vars)
        nil -> template[:subject]
      end

    body =
      case template_slug do
        login when login in ["sanbase-sign-in-mail", "neuro-sign-in", "sheets-sign-in"] ->
          login_template(vars)

        register when register in ["sanbase-sign-up-mail", "neuro-sign-up", "sheets-sign-up"] ->
          register_template(vars)

        verify when verify in ["sanbase-verify-email-mail"] ->
          verify_template(vars)
      end

    Sanbase.SimpleMailer.send_email(rcpt_email, subject, body)
  end

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

  def login_template(vars) do
    %{login_link: login_link} = vars

    """
    👋 Welcome to Santiment!

    You've requested to log in to your Santiment account. To proceed with your login, please click the secure link below:

    #{login_link}

    For security reasons this link will expire in 1 hour.

    Thank you for trusting Santiment,
    SanFam
    """
  end

  def register_template(vars) do
    %{login_link: login_link} = vars

    """
    👋 Thanks for signing-up!

    We're excited you've joined us!

    As a little necessary step, please confirm your registration below.

    #{login_link}

    For security reasons, this link will expire in 1 hour.

    Thank you for trusting Santiment,
    SanFam
    """
  end

  def verify_template(vars) do
    %{verify_link: verify_link} = vars

    """
    ✉️ Confirm your email

    Please verify that you are owner of this email in order to use it with your Sanbase account.

    #{verify_link}

    For security reasons, this link will expire in 1 hour.

    Thank you for trusting Santiment,
    SanFam
    """
  end
end
