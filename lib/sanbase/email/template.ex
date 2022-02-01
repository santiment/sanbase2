defmodule Sanbase.Email.Template do
  @sanbase_login_templates %{login: "sanbase-sign-in", register: "sanbase-sign-up"}
  @neuro_login_templates %{login: "neuro-sign-in", register: "neuro-sign-up"}
  @sheets_login_templates %{login: "sheets-sign-in", register: "sheets-sign-up"}
  @verification_email_template "sanbase_verify_email"
  @alerts_template "signals"
  @sign_up_trial_templates %{
    # immediately after sign up
    sent_welcome_email: "sanbase_post_registration",
    # on the 4th day
    sent_first_education_email: "first_edu_email",
    # on the 7th day
    sent_second_education_email: "second_edu_email",
    # 3 days before end with coupon code
    sent_trial_will_end_email: "trial_three_days_before_end",
    # when we cancel - ~ 2 hours before end
    sent_trial_finished_without_cc: "trial_finished_without_card"
  }

  @sign_up_templates %{
    # immediately after sign up
    welcome_email: "sanbase_post_registration_v2",
    # on the 4th day
    first_education_email: "first_edu_email_v2",
    # on the 6th day
    trial_suggestion: "trial_suggestion",
    # on the 7th day
    second_education_email: "second_edu_email_v2"
  }
  @post_cancellation_template "cancelled_subscription"

  @comment_notification_template "notification"
  @verify_email_weekly_digest_template "verify_email_weekly_digest"
  @monitoring_watchlist_template "monitoring_watchlist"

  def alerts_template, do: @alerts_template
  def sign_up_trial_templates, do: @sign_up_trial_templates
  def sign_up_templates, do: @sign_up_templates
  def post_cancellation_template, do: @post_cancellation_template
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
