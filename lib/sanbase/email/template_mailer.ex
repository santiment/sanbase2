defmodule Sanbase.TemplateMailer do
  use Swoosh.Mailer, otp_app: :sanbase

  require Logger

  import Swoosh.Email

  @sender_email "support@santiment.net"
  @sender_name "Santiment"

  def send(rcpt_email, template_slug, vars) do
    template = Sanbase.Email.Template.templates()[template_slug]
    vars = process_vars(vars)

    if template do
      subject =
        case template[:dynamic_subject] do
          subject when is_binary(subject) -> Sanbase.TemplateEngine.run(subject, vars)
          nil -> template[:subject]
        end

      new()
      |> to(rcpt_email)
      |> from({@sender_name, @sender_email})
      |> subject(subject)
      |> put_provider_option(:template_id, template[:id])
      |> put_provider_option(:template_error_deliver, true)
      |> put_provider_option(:template_error_reporting, "tsvetozar.p@santiment.net")
      |> put_provider_option(:variables, vars)
      |> deliver()
    else
      Logger.info("Missing email template: #{template_slug}")
      :ok
    end
  end

  # Fixme - it is only used migrate vars of already scheduled emails in the past
  # After a couple of weeks it can be removed
  defp process_vars(vars) do
    if Map.has_key?(vars, :expire_at) do
      Map.merge(vars, %{date: vars.expire_at, end_subscription_date: vars.expire_at})
    else
      vars
    end
  end
end
