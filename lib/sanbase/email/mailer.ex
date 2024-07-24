defmodule Sanbase.Mailer do
  use Oban.Worker, queue: :email_queue

  require Logger

  import Sanbase.Email.Template

  alias Sanbase.Accounts.{User, UserSettings}
  alias Sanbase.Billing.{Subscription, Product}

  @edu_templates ~w(first-edu-email second-edu-email)
  @during_trial_annual_discount_template during_trial_annual_discount_template()
  @after_trial_annual_discount_template after_trial_annual_discount_template()
  @end_of_trial_template end_of_trial_template()
  @trial_started_template trial_started_template()

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "template" => template} = args}) do
    user = User.by_id!(user_id)
    vars = args["vars"] || %{}

    # If the user does not have an email or opted out of
    # receiving educational emails just mark the job as finished.
    # In case of missing email it is better to just mark every job as
    # finished instead of not scheduling the emails at all. This is because
    # the user might enter their email at some point and we want to send
    # the rest of the emails in this case.
    with email when is_binary(email) <- user.email,
         true <- can_send?(user, template) do
      Sanbase.TemplateMailer.send(user.email, template, vars)
    else
      _ -> :ok
    end
  end

  # helpers

  defp can_send?(user, template, params \\ %{})

  defp can_send?(user, template, _params) when template in ["trial-suggestion"] do
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
        Subscription.trialing_sanbase_pro?(subscription)

      _ ->
        false
    end
  end

  defp can_send?(user, @end_of_trial_template, _params) do
    subscription = Subscription.current_subscription(user.id, Product.product_sanbase())

    case subscription do
      %Subscription{cancel_at_period_end: false} = subscription ->
        Subscription.trialing_sanbase_pro?(subscription) and has_card?(user)

      _ ->
        false
    end
  end

  defp can_send?(user, template, _params) when template == :welcome_email do
    not is_excluded_email?(user.email)
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

  # don't send post-registration email to emails that contain these tokens
  # or have digits in them by Maksim T.
  def is_excluded_email?(email) do
    tokens = [
      "gmail",
      "yahoo",
      "hotmail",
      "santiment",
      "proton",
      "icloud",
      "yandex",
      "qq.com",
      "bk.ru",
      "aol.com",
      "msn.com",
      "mail.ru",
      "rocketmail",
      "live.co",
      "me.com",
      "googlemail",
      "comcast",
      "gmx.com",
      "pm.me",
      "mailinator",
      "mac.com"
    ]

    Enum.any?(tokens, &String.contains?(email, &1)) or Regex.match?(~r/\d/, email)
  end
end
