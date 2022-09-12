defmodule Sanbase.Accounts.EmailJobs do
  import Sanbase.DateTimeUtils, only: [days_after: 1]
  import Sanbase.Email.Template

  @oban_conf_name :oban_web

  def schedule_emails_after_sign_up(user_id) do
    user = Sanbase.Accounts.User.by_id!(user_id)
    templates = Sanbase.Email.Template.sign_up_templates()

    name = Sanbase.Accounts.User.get_name(user)
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
        :trial_suggestion_job,
        scheduled_email(:trial_suggestion, templates, user, vars)
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
    user = Sanbase.Accounts.User.by_id!(subscription.user_id)
    name = Sanbase.Accounts.User.get_name(user)

    Sanbase.TemplateMailer.send("tsvetozar.penov@gmail.com", "automatic_renewal", %{
      name: name,
      username: name,
      subscription_type: subscription_type(subscription),
      charge_date: DateTime.from_unix!(charge_date_unix) |> format_date()
    })
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

  def schedule_annual_discount_emails(subscription) do
    user = Sanbase.Accounts.User.by_id!(subscription.user_id)
    name = Sanbase.Accounts.User.get_name(user)

    common_vars = %{
      name: name,
      username: name
    }

    vars_50 = Map.put(common_vars, :end_subscription_date, days_after(14) |> format_date())
    vars_35 = Map.put(common_vars, :date, days_after(30) |> format_date())

    add_email_job(subscription.user_id, during_trial_annual_discount_template(), vars_50,
      scheduled_at: days_after(12)
    )

    add_email_job(subscription.user_id, after_trial_annual_discount_template(), vars_35,
      scheduled_at: days_after(24)
    )
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
        :trial_suggestion -> days_after(6)
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
