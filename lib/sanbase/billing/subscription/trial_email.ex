defmodule Sanbase.Billing.Subscription.TrialEmail do
  @moduledoc """
  Send email on particular day of a trial with CC
  """
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  require Logger

  alias Sanbase.Repo
  alias Sanbase.Accounts.User
  alias Sanbase.Billing.Subscription

  @templates Sanbase.Email.Template.trial_email_templates()
  @free_trial_days 14
  @day_email_type_map %{
    4 => :sent_first_education_email,
    7 => :sent_second_education_email
  }

  schema "trial_emails" do
    belongs_to(:user, User)
    belongs_to(:subscription, Subscription)

    field(:sent_welcome_email, :boolean, dafault: false)
    field(:sent_first_education_email, :boolean, dafault: false)
    field(:sent_second_education_email, :boolean, dafault: false)
    field(:is_finished, :boolean, default: false)

    timestamps()
  end

  def changeset(trial_email, attrs) do
    trial_email
    |> cast(attrs, [
      :user_id,
      :subscription_id,
      :sent_welcome_email,
      :sent_first_education_email,
      :sent_second_education_email,
      :is_finished
    ])
    |> validate_required([:user_id])
    |> unique_constraint(:user_id)
    |> unique_constraint(:subscription_id)
  end

  def create(attrs) do
    %__MODULE__{} |> changeset(attrs) |> Repo.insert()
  end

  def update_trial(trial_email, attrs) do
    trial_email |> changeset(attrs) |> Repo.update()
  end

  def create_and_send_welcome_email(attrs) do
    create(attrs)
    |> case do
      {:ok, trial_email} -> send_email_async(trial_email, :sent_welcome_email)
      {:error, reason} -> {:error, reason}
    end
  end

  def send_email_on_trial_day() do
    from(te in __MODULE__, where: te.is_finished == false)
    |> Repo.all()
    |> Enum.each(fn trial_email ->
      trial_day = calc_trial_day(trial_email)

      case Map.get(@day_email_type_map, trial_day) do
        nil ->
          :ok

        email_type ->
          maybe_send_email(trial_email, email_type)
      end
    end)
  end

  def update_finished_trials() do
    free_trial_days_ago = Timex.shift(Timex.now(), days: -@free_trial_days)

    from(sut in __MODULE__,
      where: sut.is_finished == false and sut.inserted_at < ^free_trial_days_ago,
      update: [set: [is_finished: true]]
    )
    |> Repo.update_all([])
  end

  # helpers

  defp maybe_send_email(trial_email, email_type)
       when email_type in [
              :sent_first_education_email,
              :sent_second_education_email
            ] do
    subscription = Subscription.by_id(email_type.subscription_id)

    if subscription.status == "trialing" do
      do_send_email_and_mark_sent(trial_email, email_type)
    end
  end

  defp send_email_async(%__MODULE__{} = trial_email, email_type) do
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      do_send_email_and_mark_sent(trial_email, email_type)
    end)
  end

  defp do_send_email_and_mark_sent(%__MODULE__{user_id: user_id} = trial_email, email_type) do
    user = Repo.get(User, user_id)
    user_unique_str = User.get_unique_str(user)

    template = @templates[email_type]

    # User exists, we have proper template in Mandrill and this email type is not already sent
    if user && template && !Map.get(trial_email, email_type) do
      Logger.info(
        "[trial_email] Trial email template #{template} sent to: #{user.email}, name=#{user_unique_str}"
      )

      Sanbase.MandrillApi.send(template, user.email, %{name: user_unique_str})

      update_trial(trial_email, %{email_type => true})
    end
  end

  defp calc_trial_day(%__MODULE__{inserted_at: inserted_at}) do
    Timex.diff(Timex.now(), inserted_at, :days)
  end
end
