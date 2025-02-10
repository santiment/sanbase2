defmodule Sanbase.Email.Template do
  @moduledoc false
  @templates %{
    "sanr-network-welcome" => %{
      id: 5_078_949,
      subject: "Sanr.Network Node Holder Application Form",
      required_vars: []
    },
    "alpha-naratives-welcome" => %{
      id: 5_087_218,
      subject: "Thank you for joining the Alpha Narratives waiting list!",
      required_vars: []
    },
    "sanbase-sign-in-mail" => %{
      id: 4_128_976,
      subject: "Login link",
      required_vars: [:login_link]
    },
    "sanbase-sign-up-mail" => %{
      id: 4_127_535,
      subject: "Confirm your registration",
      required_vars: [:login_link]
    },
    "sheets-sign-in" => %{
      id: 4_129_863,
      subject: "Login link",
      required_vars: [:login_link]
    },
    "sheets-sign-up" => %{
      id: 4_129_866,
      subject: "Confirm your registration",
      required_vars: [:login_link]
    },
    "neuro-sign-in" => %{
      id: 4_131_877,
      subject: "Login link",
      required_vars: [:login_link]
    },
    "neuro-sign-up" => %{
      id: 4_131_890,
      subject: "Confirm your registration",
      required_vars: [:login_link]
    },
    "sanbase-post-registration-mail" => %{
      id: 4_127_351,
      subject: "Welcome to Sanbase",
      required_vars: [:username]
    },
    "sanbase-verify-email-mail" => %{
      id: 4_127_547,
      subject: "Verify your email",
      required_vars: [:verify_link]
    },
    "pro-started" => %{
      id: 4_127_555,
      subject: "Enjoy your upgrade!",
      required_vars: [:subscription_type, :username, :subscription_duration]
    },
    "cancelled-subscription-mail" => %{
      id: 4_127_563,
      subject: "You’ve cancelled your subscription",
      required_vars: [:subscription_type, :subscription_enddate]
    },
    "post-cancellation-email2" => %{
      id: 6_375_587,
      subject: "Subscription Cancellation Feedback Request",
      required_vars: []
    },
    "free-trial-started" => %{
      id: 4_127_573,
      subject: "Enjoy your free Sanbase trial!",
      required_vars: [:subscription_type, :subscription_duration, :username]
    },
    "trial-end-mail" => %{
      id: 4_127_582,
      subject: "Your trial is ending and card will be charged!",
      required_vars: [:subscription_type, :subscription_duration, :name]
    },
    "50-percent-discount-offer" => %{
      id: 4_127_588,
      subject: "Get your one-time 50% offer",
      required_vars: [:name, :end_subscription_date]
    },
    "35-percent-discount-offer" => %{
      id: 4_127_592,
      subject: "Get your one-time 35% offer",
      required_vars: [:name, :date]
    },
    "signal-mail" => %{
      id: 4_127_602,
      subject: "Sanbase alert!",
      dynamic_subject: "Sanbase alert: {{username}}",
      required_vars: [:username, :payload]
    },
    "first-edu-email" => %{
      id: 4_132_905,
      subject: "How to time Ethereum tops with just 3 indicators | Santiment Academy",
      required_vars: []
    },
    "second-edu-email" => %{
      id: 4_132_860,
      subject: "Sanbase tips",
      required_vars: [:name]
    },
    "trial-suggestion" => %{
      id: 4_132_855,
      subject: "Start your free trial today",
      required_vars: []
    },
    "slip-away-users" => %{
      id: 4_132_877,
      subject: "Explore the power of our customisable charts",
      required_vars: [:name]
    },
    "notification" => %{
      id: 4_127_647,
      subject: "Your Sanbase activity",
      required_vars: []
    },
    "automatic_renewal" => %{
      id: 4_161_751,
      subject: "Your subscription will renew soon",
      required_vars: [:name, :subscription_type, :charge_date]
    }
  }

  # Sign up / Sign in from app.santiment.net
  @sanbase_login_templates %{login: "sanbase-sign-in-mail", register: "sanbase-sign-up-mail"}

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
    first_education_email: "first-edu-email",
    # on the 6th day
    trial_suggestion: "trial-suggestion",
    # on the 7th day
    second_education_email: "second-edu-email"
  }

  # Send when Sanbase pro subscription starts
  @pro_subscription_stared_template "pro-started"

  # Send on subscription cancellation
  @post_cancellation_template "cancelled-subscription-mail"

  @post_cancellation_template2 "post-cancellation-email2"

  # Send on free trial start
  @trial_started_template "free-trial-started"

  # Send 3 days before trial ends
  @end_of_trial_template "trial-end-mail"

  @automatic_renewal_template "automatic_renewal"

  # Send after 2 weeks of inactivity.
  # FIXME- currently not send, inactivity should be defined
  # @slip_away_template "slip-away-users"

  # Send on new comment for insights and timeline events entities
  # The recipient is either author of the entity, previous commenter or the comment is a reply
  @comment_notification_template "notification"

  @verify_email_weekly_digest_template "verify_email_weekly_digest"

  def templates, do: @templates
  def alerts_template, do: @alerts_template
  def sign_up_templates, do: @sign_up_templates
  def pro_subscription_stared_template, do: @pro_subscription_stared_template
  def post_cancellation_template, do: @post_cancellation_template
  def post_cancellation_template2, do: @post_cancellation_template2
  def end_of_trial_template, do: @end_of_trial_template
  def trial_started_template, do: @trial_started_template
  def automatic_renewal_template, do: @automatic_renewal_template

  def comment_notification_template, do: @comment_notification_template
  def verify_email_weekly_digest_template, do: @verify_email_weekly_digest_template
  def verification_email_template, do: @verification_email_template

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
