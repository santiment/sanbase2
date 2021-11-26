defmodule Sanbase.Accounts.EmailJobs do
  import Sanbase.DateTimeUtils, only: [days_after: 1]

  @oban_conf_name :oban_web

  def schedule_emails_after_sign_up(user_id) do
    user = Sanbase.Accounts.User.by_id!(user_id)
    templates = Sanbase.Email.Template.sign_up_templates()
    user_unique_str = Sanbase.Accounts.User.get_unique_str(user)

    vars = %{name: user_unique_str}

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

  def send_post_cancellation_email(subscription) do
    template = Sanbase.Email.Template.post_cancellation_template()

    vars = %{
      subscription_type: "Sanbase #{String.capitalize(subscription.plan.name)}",
      end_subscription_date: Timex.format!(subscription.current_period_end, "{Mfull} {D}, {YYYY}")
    }

    data =
      Sanbase.Mailer.new(%{
        user_id: subscription.user_id,
        template: template,
        vars: vars
      })

    Oban.insert(@oban_conf_name, data)
  end

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
