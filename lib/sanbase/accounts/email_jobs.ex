defmodule Sanbase.Accounts.EmailJobs do
  import Sanbase.DateTimeUtils, only: [days_after: 1, seconds_after: 1]
  import Sanbase.Email.Template

  @oban_conf_name :oban_web

  def send_automatic_renewal_email(subscription, charge_date_unix) do
    user = Sanbase.Accounts.User.by_id!(subscription.user_id)
    name = Sanbase.Accounts.User.get_name(user)

    vars = %{
      name: name,
      username: name,
      subscription_type: subscription_type(subscription),
      charge_date: DateTime.from_unix!(charge_date_unix) |> format_date()
    }

    add_email_job(subscription.user_id, automatic_renewal_template(), vars)
  end

  def send_trial_started_email(subscription) do
    user = Sanbase.Accounts.User.by_id!(subscription.user_id)
    name = Sanbase.Accounts.User.get_name(user)

    vars = %{
      name: name,
      username: name,
      subscription_type: subscription_type(subscription)
    }

    add_email_job(subscription.user_id, trial_started_template(), vars)
  end

  def schedule_trial_will_end_email(subscription) do
    user = Sanbase.Accounts.User.by_id!(subscription.user_id)
    name = Sanbase.Accounts.User.get_name(user)

    vars = %{
      name: name,
      username: name,
      subscription_type: subscription_type(subscription),
      subscription_duration: subscription.plan.interval <> "ly"
    }

    add_email_job(user.id, end_of_trial_template(), vars, scheduled_at: days_after(11))
  end

  def send_pro_started_email(subscription) do
    user = Sanbase.Accounts.User.by_id!(subscription.user_id)
    name = Sanbase.Accounts.User.get_name(user)

    vars = %{
      name: name,
      username: name,
      subscription_type: subscription_type(subscription),
      subscription_duration: subscription.plan.interval
    }

    add_email_job(
      subscription.user_id,
      Sanbase.Email.Template.pro_subscription_stared_template(),
      vars
    )
  end

  def send_post_cancellation_email(subscription) do
    template = Sanbase.Email.Template.post_cancellation_template()

    vars = %{
      subscription_type: subscription_type(subscription),
      subscription_enddate: format_date(subscription.current_period_end)
    }

    add_email_job(subscription.user_id, template, vars)
  end

  def schedule_post_cancellation_email2(subscription) do
    template = Sanbase.Email.Template.post_cancellation_template2()

    add_email_job(subscription.user_id, template, %{}, scheduled_at: seconds_after(300))
  end

  def add_email_job(user_id, email_template, email_vars, opts \\ []) do
    data =
      Sanbase.Mailer.new(
        %{
          user_id: user_id,
          template: email_template,
          vars: email_vars
        },
        opts
      )

    Oban.insert(@oban_conf_name, data)
  end

  def format_date(datetime) do
    Timex.format!(datetime, "{Mfull} {D}, {YYYY}")
  end

  def subscription_type(subscription) do
    plan_name =
      case subscription.plan.name do
        "PRO" -> "PRO"
        "PRO_PLUS" -> "PRO+"
        "MAX" -> "MAX"
        plan -> plan
      end

    "Sanbase #{plan_name}"
  end
end
