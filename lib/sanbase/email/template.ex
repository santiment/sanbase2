defmodule Sanbase.Email.Template do
  @sanbase_login_templates %{login: "sanbase-welcome-back-mail", register: "sanbase-sign-up-mail"}
  @neuro_login_templates %{login: "neuro-sign-in", register: "neuro-sign-up"}
  @sheets_login_templates %{login: "sheets-sign-in", register: "sheets-sign-up"}
  @verification_email_template "sanbase-verify-email-mail"
  @alerts_template "signals"

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
  @post_cancellation_template "cancelled-subscription-mail"
  @end_of_trial_template "trial-end-mail"

  @comment_notification_template "notification"
  @verify_email_weekly_digest_template "verify_email_weekly_digest"
  @monitoring_watchlist_template "monitoring_watchlist"

  def alerts_template, do: @alerts_template
  def sign_up_templates, do: @sign_up_templates
  def post_cancellation_template, do: @post_cancellation_template
  def end_of_trial_template, do: @end_of_trial_template

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
