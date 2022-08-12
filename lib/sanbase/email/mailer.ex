defmodule Sanbase.Mailer do
  use Oban.Worker, queue: :email_queue
  use Swoosh.Mailer, otp_app: :sanbase

  require Logger

  import Sanbase.Email.Template
  import Swoosh.Email

  alias Sanbase.Accounts.{User, UserSettings}
  alias Sanbase.Billing.{Subscription, Product}

  @sender_email "support@santiment.net"
  @sender_name "Santiment"

  @edu_templates ~w(first_edu_email_v2 second_edu_email_v2)
  @during_trial_annual_discount_template during_trial_annual_discount_template()
  @after_trial_annual_discount_template after_trial_annual_discount_template()
  @end_of_trial_template end_of_trial_template()
  @trial_started_template trial_started_template()

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "template" => template} = args}) do
    user = User.by_id!(user_id)
    vars = args["vars"] || %{}
    opts = args["opts"] || %{}

    # If the user does not have an email or opted out of
    # receiving educational emails just mark the job as finished.
    # In case of missing email it is better to just mark every job as
    # finished instead of not scheduling the emails at all. This is because
    # the user might enter their email at some point and we want to send
    # the rest of the emails in this case.
    with email when is_binary(email) <- user.email,
         true <- can_send?(user, template) do
      template_send(user.email, template, vars)
    else
      _ -> :ok
    end
  end

  def send_sign_in_email(rcpt_email, login_link) do
    sender_email = "support@santiment.net"
    subject = "Login link"

    body = """
    Welcome back!

    Santiment doesn't make you remember yet another password. Just click the link below and you’re in.

    #{login_link}
    """

    new()
    |> to(rcpt_email)
    |> from({"Santiment", sender_email})
    |> subject(subject)
    |> text_body(body)
    |> Sanbase.Mailer.deliver()
  end

  def send_sign_up_email(rcpt_email, login_link) do
    sender_email = "support@santiment.net"
    subject = "Login link"

    body = """
    Thanks for signing-up!

    We’re excited you’ve joined us!

    As a little necessary step, please confirm your registration below.

    #{login_link}
    """

    new()
    |> to(rcpt_email)
    |> from({"Santiment", sender_email})
    |> subject(subject)
    |> text_body(body)
    |> Sanbase.Mailer.deliver()
  end

  def send_verify_email(rcpt_email, verify_link) do
    sender_email = "support@santiment.net"
    subject = "Verify your email"

    body = """
    Confirm your email

    Please verify that you are the owner of this email in order to use it with your Sanbase account.

    #{verify_link}

    Thank you for trusting Santiment!
    """

    new()
    |> to(rcpt_email)
    |> from({"Santiment", sender_email})
    |> subject(subject)
    |> text_body(body)
    |> Sanbase.Mailer.deliver()
  end

  def send_alert_email("tsvetozar.penov@gmail.com" = rcpt_email, args) do
    sender_email = "support@santiment.net"
    subject = "Signal alert!"

    body = """
    <p>Hey, #{args.name}</p>

    #{args.payload_html}
    """

    new()
    |> to(rcpt_email)
    |> from({"Santiment", sender_email})
    |> subject(subject)
    |> html_body(body)
    |> Sanbase.Mailer.deliver()
  end

  def send_alert_email(_, _name, _payload_html), do: {:ok, :sent}

  def send_welcome_email(rcpt_email, template_id, vars) do
    sender_email = "support@santiment.net"
    subject = "Welcome to Sanbase"

    new()
    |> to(rcpt_email)
    |> from({"Santiment", sender_email})
    |> subject(subject)
    |> put_provider_option(:template_id, template_id)
    |> put_provider_option(:template_error_deliver, true)
    |> put_provider_option(:template_error_reporting, "tsvetozar.penov@gmail.com")
    |> put_provider_option(:variables, vars)
    |> Sanbase.Mailer.deliver()
  end

  def template_send(rcpt_email, template_slug, vars) do
    template = templates()[template_slug]

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
      |> Sanbase.Mailer.deliver()
    else
      Logger.info("Missing email template: #{template_slug}")
      :ok
    end
  end

  # helpers

  defp can_send?(user, template, params \\ %{})

  defp can_send?(user, template, _params) when template in [:trial_suggestion] do
    not Subscription.user_has_sanbase_pro?(user.id)
  end

  defp can_send?(user, template, _params) when template in @edu_templates do
    user = Sanbase.Repo.preload(user, :user_settings)

    UserSettings.settings_for(user).is_subscribed_edu_emails
  end

  defp can_send?(user, @trial_started_template, _params) do
    subscription = Subscription.current_subscription(user.id, Product.product_sanbase())

    case subscription do
      %Subscription{} = subscription ->
        Subscription.is_trialing_sanbase_pro?(subscription)

      _ ->
        false
    end
  end

  defp can_send?(user, @end_of_trial_template, _params) do
    subscription = Subscription.current_subscription(user.id, Product.product_sanbase())

    case subscription do
      %Subscription{cancel_at_period_end: false} = subscription ->
        Subscription.is_trialing_sanbase_pro?(subscription) and has_card?(user)

      _ ->
        false
    end
  end

  defp can_send?(user, template, _params)
       when template == @during_trial_annual_discount_template do
    res = Sanbase.Billing.Subscription.annual_discount_eligibility(user.id)
    res.is_eligible and res.discount.percent_off == 50
  end

  defp can_send?(user, template, _params)
       when template == @after_trial_annual_discount_template do
    res = Sanbase.Billing.Subscription.annual_discount_eligibility(user.id)
    res.is_eligible and res.discount.percent_off == 35
  end

  defp can_send?(_user, _template, _params), do: true

  defp has_card?(user) do
    case Sanbase.StripeApi.fetch_default_card(user) do
      {:ok, customer} -> not is_nil(customer.default_source)
      _ -> false
    end
  end
end
