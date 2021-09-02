defmodule Sanbase.Accounts.Email do
  def schedule_emails_after_sign_up(user) do
    sign_up_templates = Sanbase.Email.Template.sign_up_templates()
    user_unique_str = Sanbase.Accounts.User.get_unique_str(user)

    vars = %{name: user_unique_str}

    now = Timex.now()

    after_days = fn now, days ->
      Timex.shift(now, days: days)
    end

    Ecto.Multi.new()
    |> Oban.insert(
      :welcome_email_job,
      Sanbase.Mailer.new(%{
        user_id: user.id,
        template: sign_up_templates[:welcome_email],
        vars: vars
      })
    )
    |> Oban.insert(
      :first_education_email_job,
      Sanbase.Mailer.new(
        %{
          user_id: user.id,
          template: sign_up_templates[:first_education_email],
          vars: vars
        },
        scheduled_at: after_days.(now, 4)
      )
    )
    |> Oban.insert(
      :trial_suggestion_job,
      Sanbase.Mailer.new(
        %{
          user_id: user.id,
          template: sign_up_templates[:trial_suggestion],
          vars: vars
        },
        scheduled_at: after_days.(now, 6)
      )
    )
    |> Oban.insert(
      :second_education_email_job,
      Sanbase.Mailer.new(
        %{
          user_id: user.id,
          template: sign_up_templates[:second_education_email],
          vars: vars
        },
        scheduled_at: after_days.(now, 7)
      )
    )
    |> Sanbase.Repo.transaction()
  end
end
