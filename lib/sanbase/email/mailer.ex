defmodule Sanbase.Mailer do
  use Oban.Worker, queue: :email_queue

  alias Sanbase.Accounts.User

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "template" => template} = args}) do
    user = User.by_id!(user_id)
    vars = args["vars"] || %{}
    opts = args["opts"] || %{}

    case user.email do
      nil ->
        # If the user does not have an email just mark the job as finished.
        # In case of missing email it is better to just mark every job as
        # finished instead of not scheduling the emails at all. This is because
        # the user might enter their email at some point and we want to send
        # the rest of the emails in this case.
        :ok

      _ ->
        Sanbase.MandrillApi.send(template, user.email, vars, opts)
    end
  end
end
