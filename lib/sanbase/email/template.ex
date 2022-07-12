defmodule Sanbase.Email.Template do
  # Sign up / Sign in from app.santiment.net
  @sanbase_login_templates %{login: "sanbase-welcome-back-mail", register: "sanbase-sign-up-mail"}

  # Sign up / Sign in from api.santiment.net
  @neuro_login_templates %{login: "neuro-sign-in", register: "neuro-sign-up"}

  # Sign up / Sign in from sheets.santiment.net
  @sheets_login_templates %{login: "sheets-sign-in", register: "sheets-sign-up"}

  # Email verification template
  @verification_email_template "sanbase-verify-email-mail"

  # Alert fired template
  @alerts_template "signal-mail"

  # Post sign up templates
  @sign_up_templates %{
    # immediately after sign up
    welcome_email: "sanbase-post-registration-mail",
    # on the 4th day
    first_education_email: "first_edu_email_v2",
    # on the 6th day
    trial_suggestion: "trial_suggestion",
    # on the 7th day
    second_education_email: "second_edu_email_v2"
  }

  # Send when Sanbase pro subscription starts
  @pro_subscription_stared_template "pro-started"

  # Send on subscription cancellation
  @post_cancellation_template "cancelled-subscription-mail"

  # Send on free trial start
  @trial_started_template "free-trial-started"

  # Send 3 days before trial ends
  @end_of_trial_template "trial-end-mail"

  # Send 2 days before trial ends
  @during_trial_annual_discount_template "50-percent-discount-offer"

  # Send once - 1 week before monthly Sanbase Pro ends
  @after_trial_annual_discount_template "35-percent-discount-offer"

  # Send after 2 weeks of inactivity.
  # FIXME- currently not send, inactivity should be defined
  # @slip_away_template "slip-away-users"

  # Send on new comment for insights and timeline events entities
  # The recipient is either author of the entity, previous commenter or the comment is a reply
  @comment_notification_template "notification"

  @verify_email_weekly_digest_template "verify_email_weekly_digest"
  @monitoring_watchlist_template "monitoring_watchlist"

  def alerts_template, do: @alerts_template
  def sign_up_templates, do: @sign_up_templates
  def pro_subscription_stared_template, do: @pro_subscription_stared_template
  def post_cancellation_template, do: @post_cancellation_template
  def end_of_trial_template, do: @end_of_trial_template
  def trial_started_template, do: @trial_started_template
  def during_trial_annual_discount_template, do: @during_trial_annual_discount_template
  def after_trial_annual_discount_template, do: @after_trial_annual_discount_template

  def comment_notification_template, do: @comment_notification_template
  def verify_email_weekly_digest_template, do: @verify_email_weekly_digest_template
  def monitoring_watchlist_template, do: @monitoring_watchlist_template
  def verification_email_template(), do: @verification_email_template

  def choose_login_template(origin_url, first_login?: true) when is_binary(origin_url) do
    template_by_product(origin_url, :register)
  end

  def choose_login_template(origin_url, first_login?: false) when is_binary(origin_url) do
    template_by_product(origin_url, :login)
  end

  def choose_login_template(_, first_login?: true), do: @sanbase_login_templates[:register]
  def choose_login_template(_, first_login?: false), do: @sanbase_login_templates[:login]

  defp template_by_product(origin_url, template) do
    cond do
      String.contains?(origin_url, ["neuro", "api"]) -> @neuro_login_templates[template]
      String.contains?(origin_url, "sheets") -> @sheets_login_templates[template]
      true -> @sanbase_login_templates[template]
    end
  end
end
