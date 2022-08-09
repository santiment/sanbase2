defmodule Sanbase.Mailer do
  use Oban.Worker, queue: :email_queue
  use Swoosh.Mailer, otp_app: :sanbase

  import Sanbase.Email.Template
  import Swoosh.Email

  alias Sanbase.Accounts.{User, UserSettings}
  alias Sanbase.Billing.{Subscription, Product}

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
      Sanbase.MandrillApi.send(template, user.email, vars, opts)
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
    |> from(sender_email)
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
    |> from(sender_email)
    |> subject(subject)
    |> text_body(body)
    |> Sanbase.Mailer.deliver()
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
