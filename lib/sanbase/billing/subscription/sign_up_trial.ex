defmodule Sanbase.Billing.Subscription.SignUpTrial do
  @moduledoc """
  Module for creating free trial and sending follow-up emails after user signs up.
  We send 4 types of emails in the span of the 14-day free trial:
  * A welcome email - immediately post registration.
  * An email at the 3rd day of free trial.
  * An email at the 11th day of free trial.
  * And an email when the free trial expired.
  A cron job runs twice a day and makes sure to send email at the proper day of the user's trial.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  require Logger

  alias Sanbase.Auth.User
  alias Sanbase.Billing.Subscription.PromoTrial
  alias Sanbase.Repo
  alias Sanbase.Billing.Plan

  @free_trial_days 14
  # Free trial plans are Sanbase PRO plans
  @free_trial_plans [Plan.Metadata.sanbase_pro()]

  @day_email_type_map %{
    3 => :sent_3day_email,
    11 => :sent_11day_email,
    14 => :sent_end_trial_email
  }

  @templates %{
    sent_welcome_email: "sanbase-post-registration"
  }

  schema "sign_up_trials" do
    belongs_to(:user, User)

    field(:sent_welcome_email, :boolean, dafault: false)
    field(:sent_3day_email, :boolean, dafault: false)
    field(:sent_11day_email, :boolean, dafault: false)
    field(:sent_end_trial_email, :boolean, dafault: false)

    timestamps()
  end

  @doc false
  def changeset(sign_up_trial, attrs) do
    sign_up_trial
    |> cast(attrs, [
      :user_id,
      :sent_welcome_email,
      :sent_3day_email,
      :sent_11day_email,
      :sent_end_trial_email
    ])
    |> validate_required([:user_id])
    |> unique_constraint(:user_id)
  end

  def send_emails() do
    from(sut in __MODULE__, preload: [:user])
    |> Repo.all()
    |> Enum.each(&maybe_send_email/1)
  end

  def by_user_id(user_id) do
    Repo.get_by(__MODULE__, user_id: user_id)
  end

  def create(user_id) do
    %__MODULE__{} |> changeset(%{user_id: user_id}) |> Repo.insert()
  end

  def update(sign_up_trial, params) do
    sign_up_trial |> changeset(params) |> Repo.update()
  end

  def create_subscription(user_id) do
    with {:ok, sign_up_trial} <- create(user_id),
         {:ok, subscriptions} <-
           PromoTrial.create_promo_trial(%{
             user_id: user_id,
             plans: @free_trial_plans,
             trial_days: @free_trial_days
           }) do
      send_email_async(sign_up_trial, :sent_welcome_email)
      {:ok, subscriptions}
    else
      {:error, error} ->
        {:error, error}
    end
  end

  def send_email_async(%__MODULE__{} = sign_up_trial, email_type) do
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      send_email(sign_up_trial, email_type)
    end)
  end

  defp send_email(%__MODULE__{user_id: user_id} = sign_up_trial, :sent_welcome_email = email_type) do
    template = @templates[email_type]
    user = Repo.get(User, user_id)

    do_send_email(user, template)
    update(sign_up_trial, %{email_type => true})
  end

  defp do_send_email(user, template) do
    Logger.info(
      "Trial email template #{template} sent to: #{user.email}, name=#{
        user.username || user.email
      }"
    )

    Sanbase.MandrillApi.send(template, user.email, %{name: user.username || user.email}, %{
      merge_language: "handlebars"
    })
  end

  defp maybe_send_email(%__MODULE__{user: user, inserted_at: inserted_at} = sign_up_trial) do
    trial_day = calc_trial_day(inserted_at)
    email_type = @day_email_type_map[trial_day]

    if email_type && !sign_up_trial[email_type] do
      template = @templates[email_type]

      do_send_email(user, template)

      update(sign_up_trial, %{email_type => true})
    end
  end

  defp calc_trial_day(inserted_at) do
    Timex.diff(Timex.now(), inserted_at, :days)
  end
end
