defmodule Sanbase.Accounts.EmailJobs do
  @moduledoc false
  import Sanbase.DateTimeUtils, only: [days_after: 1, seconds_after: 1]
  import Sanbase.Email.Template

  alias Sanbase.Accounts.User
  alias Sanbase.Email.Template

  @oban_conf_name :oban_web

  def schedule_emails_after_sign_up(user_id) do
    user = User.by_id!(user_id)
    templates = Template.sign_up_templates()

    name = User.get_name(user)
    vars = %{name: name, username: name}

    multi = Ecto.Multi.new()

    multi =
      Oban.insert(
        @oban_conf_name,
        multi,
        :welcome_email_job,
        scheduled_email(:welcome_email, templates, user, vars)
      )

    multi =
      Oban.insert(
        @oban_conf_name,
        multi,
        :first_education_email_job,
        scheduled_email(:first_education_email, templates, user, vars)
      )

    multi =
      Oban.insert(
        @oban_conf_name,
        multi,
        :second_education_email_job,
        scheduled_email(:second_education_email, templates, user, vars)
      )

    Sanbase.Repo.transaction(multi)
  end

  def send_automatic_renewal_email(subscription, charge_date_unix) do
    user = User.by_id!(subscription.user_id)
    name = User.get_name(user)

    vars = %{
      name: name,
      username: name,
      subscription_type: subscription_type(subscription),
      charge_date: charge_date_unix |> DateTime.from_unix!() |> format_date()
    }

    add_email_job(subscription.user_id, automatic_renewal_template(), vars)
  end

  def send_trial_started_email(subscription) do
    user = User.by_id!(subscription.user_id)
    name = User.get_name(user)

    vars = %{
      name: name,
      username: name,
      subscription_type: subscription_type(subscription)
    }

    add_email_job(subscription.user_id, trial_started_template(), vars)
  end

  def schedule_trial_will_end_email(subscription) do
    user = User.by_id!(subscription.user_id)
    name = User.get_name(user)

    vars = %{
      name: name,
      username: name,
      subscription_type: subscription_type(subscription),
      subscription_duration: subscription.plan.interval <> "ly"
    }

    add_email_job(user.id, end_of_trial_template(), vars, scheduled_at: days_after(11))
  end

  def send_pro_started_email(subscription) do
    user = User.by_id!(subscription.user_id)
    name = User.get_name(user)

    vars = %{
      name: name,
      username: name,
      subscription_type: subscription_type(subscription),
      subscription_duration: subscription.plan.interval
    }

    add_email_job(
      subscription.user_id,
      Template.pro_subscription_stared_template(),
      vars
    )
  end

  def send_post_cancellation_email(subscription) do
    template = Template.post_cancellation_template()

    vars = %{
      subscription_type: subscription_type(subscription),
      subscription_enddate: format_date(subscription.current_period_end)
    }

    add_email_job(subscription.user_id, template, vars)
  end

  def schedule_post_cancellation_email2(subscription) do
    template = Template.post_cancellation_template2()

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

  # Private

  defp scheduled_email(email_type, templates, user, vars) do
    scheduled_at =
      case email_type do
        :welcome_email -> nil
        :first_education_email -> days_after(4)
        :second_education_email -> days_after(7)
      end

    Sanbase.Mailer.new(
      %{
        user_id: user.id,
        template: templates[email_type],
        vars: vars
      },
      scheduled_at: scheduled_at
    )
  end
end
