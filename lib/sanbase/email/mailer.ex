defmodule Sanbase.Mailer do
  use Oban.Worker, queue: :email_queue

  alias Sanbase.Accounts.User

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "template" => template} = args}) do
    user = User.by_id!(user_id)
    vars = args["vars"] || %{}
    opts = args["opts"] || %{}

    Sanbase.MandrillApi.send(template, user.email, vars, opts)
  end
end
