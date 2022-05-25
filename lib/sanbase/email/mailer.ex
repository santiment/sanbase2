defmodule Sanbase.Mailer do
  use Oban.Worker, queue: :email_queue

  alias Sanbase.Accounts.User

  @edu_templates ~w(first_edu_email_v2 second_edu_email_v2)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "template" => template} = args}) do
    user = User.by_id!(user_id)
    vars = args["vars"] || %{}
    opts = args["opts"] || %{}

    # If the user does not have an email or opted out of
    # receiving educational emails just mark the job as finished.
    # In case of missing email it is better to just mark every job as
    # finished instead of not scheduling the emails at all. This is because
    # the user might enter their email at some point and we want to send
    # the rest of the emails in this case.
    with email when is_binary(email) <- user.email,
         true <- can_send_edu_email?(user, template) do
      Sanbase.MandrillApi.send(template, user.email, vars, opts)
    else
      _ -> :ok
    end
  end

  defp can_send_edu_email?(user, template) when template in @edu_templates do
    user = Sanbase.Repo.preload(user, :user_settings)

    user.user_settings.settings.is_subscribed_edu_emails
  end

  defp can_send_edu_email?(_user, _template), do: true
end
