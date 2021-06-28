defmodule Sanbase.Billing.Subscription.SignUpTrial do
  @moduledoc """
  Module for creating free trial and sending follow-up emails after user signs
  up. We send 6 types of emails in the span of the 14-day free trial:

  1. A welcome email - immediately post registration.
  2. An educational email on **day 4** of free trial.
  3. A second educational email on **day 7** of free trial
  4. An email with coupon **3 days before free trial ends**.
  5. An email to users with credit card **1 day before charging them**.
  6. An email to users without credit card when we cancel expired free trial.

  A cron job runs twice a day and makes sure to send email at the proper day of
  the user's trial.
  """
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset
  # import Sanbase.Billing.EventEmitter, only: [emit_event: 3]

  require Logger

  alias Sanbase.Accounts.User
  alias Sanbase.Billing.Subscription.PromoTrial
  alias Sanbase.Repo
  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.{Subscription, Product}
  alias Sanbase.StripeApi

  @free_trial_days 14
  # Free trial plans are Sanbase PRO plans
  @free_trial_plans [Plan.Metadata.current_free_trial_plan()]

  @day_email_type_map %{
    4 => :sent_first_education_email,
    7 => :sent_second_education_email
  }

  @templates Sanbase.Email.Template.sign_up_trial_templates()

  schema "sign_up_trials" do
    belongs_to(:user, User)
    belongs_to(:subscription, Subscription)

    field(:sent_welcome_email, :boolean, dafault: false)
    field(:sent_first_education_email, :boolean, dafault: false)
    field(:sent_second_education_email, :boolean, dafault: false)
    field(:sent_trial_will_end_email, :boolean, dafault: false)
    field(:sent_cc_will_be_charged, :boolean, dafault: false)
    field(:sent_trial_finished_without_cc, :boolean, dafault: false)
    field(:is_finished, :boolean, default: false)

    timestamps()
  end

  @doc false
  def changeset(sign_up_trial, attrs) do
    sign_up_trial
    |> cast(attrs, [
      :user_id,
      :subscription_id,
      :sent_welcome_email,
      :sent_first_education_email,
      :sent_second_education_email,
      :sent_trial_will_end_email,
      :sent_cc_will_be_charged,
      :sent_trial_finished_without_cc,
      :is_finished
    ])
    |> validate_required([:user_id])
    |> unique_constraint(:user_id)
    |> unique_constraint(:subscription_id)
  end

  def by_user_id(user_id) do
    from(sut in __MODULE__,
      where: sut.user_id == ^user_id and sut.is_finished == false,
      preload: [:subscription]
    )
    |> Repo.one()
  end

  def by_subscription_id(subscription_id) do
    from(sut in __MODULE__,
      where: sut.subscription_id == ^subscription_id and sut.is_finished == false,
      preload: [:subscription]
    )
    |> Repo.one()
  end

  def create(user_id) do
    %__MODULE__{}
    |> changeset(%{user_id: user_id})
    |> Repo.insert()
  end

  def remove_sign_up_trial(user) do
    case by_user_id(user.id) do
      %__MODULE__{} = sign_up_trial ->
        cancel_trial_when_user_subscribed(sign_up_trial)

      _ ->
        :ok
    end
  end

  def trial_end_dt(user) do
    case by_user_id(user.id) do
      %__MODULE__{inserted_at: inserted_at} ->
        Timex.shift(inserted_at, days: @free_trial_days)

      _ ->
        nil
    end
  end

  @doc """
  Create trial only if user is not marked registered.
  """
  def create_trial_subscription(user_id) do
    with {:ok, %User{is_registered: false}} <- User.by_id(user_id),
         {:ok, sign_up_trial} <- create(user_id),
         {:ok, sign_up_trial} <- create_promo_trial(sign_up_trial) do
      send_email_async(sign_up_trial, :sent_welcome_email)

      {:ok, sign_up_trial}
    end
  end

  # scheduled to run once a day
  def send_email_on_trial_day() do
    from(sut in __MODULE__, where: sut.is_finished == false)
    |> Repo.all()
    |> Enum.each(fn sign_up_trial ->
      trial_day = calc_trial_day(sign_up_trial)

      case Map.get(@day_email_type_map, trial_day) do
        nil ->
          :ok

        email_type ->
          maybe_send_email(sign_up_trial, email_type)
      end
    end)
  end

  # scheduled to run every 10 mins
  def update_finished_trials() do
    free_trial_days_ago = Timex.shift(Timex.now(), days: -@free_trial_days)

    from(sut in __MODULE__,
      where: sut.is_finished == false and sut.inserted_at < ^free_trial_days_ago,
      update: [set: [is_finished: true]]
    )
    |> Repo.update_all([])
  end

  def handle_trial_will_end(stripe_subscription_id) do
    with {:ok, subscription} <- get_trialing_subscription(stripe_subscription_id),
         {:ok, sign_up_trial} <- get_trial_with_not_sent_email(subscription) do
      do_send_email_and_mark_sent(sign_up_trial, :sent_trial_will_end_email)
      {:ok, "Trial will end email is sent for subscription_id: #{stripe_subscription_id}"}
    end
  end

  def maybe_send_trial_finished_email(subscription) do
    Repo.get_by(__MODULE__,
      user_id: subscription.user_id,
      subscription_id: subscription.id,
      is_finished: false
    )
    |> case do
      %__MODULE__{sent_trial_finished_without_cc: false} = sign_up_trial ->
        do_send_email_and_mark_sent(sign_up_trial, :sent_trial_finished_without_cc)

      _ ->
        :ok
    end
  end

  @doc """
  Cancel trialing subscriptions so customers are not charged if they have attached card.
  * For Sanbase PRO cancel those:
   1. About to expire (in 2 hours)
   2. There is a record in SignUpTrials (otherwise the subscription might be with transferred trial)
  and send an email for finished trial.

  * For other plans - cancel everything.
  """
  def cancel_about_to_expire_trials() do
    now = Timex.now()
    after_2_hours = Timex.shift(now, hours: 2)

    from(s in Subscription,
      where:
        s.status == "trialing" and
          s.trial_end >= ^now and s.trial_end <= ^after_2_hours
    )
    |> Repo.all()
    |> Enum.each(&maybe_send_email_and_delete_subscription/1)
  end

  def send_email_async(%__MODULE__{} = sign_up_trial, email_type) do
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      do_send_email_and_mark_sent(sign_up_trial, email_type)
    end)
  end

  # Helper functions

  defp cancel_trial_when_user_subscribed(sign_up_trial) do
    case StripeApi.delete_subscription(sign_up_trial.subscription.stripe_id) do
      {:ok, _} ->
        update_trial(sign_up_trial, %{is_finished: true})

      # Subscription is already cancelled - update locally
      {:error, %Stripe.Error{extra: %{http_status: 404}}} ->
        update_trial(sign_up_trial, %{is_finished: true})

      {:error, other} ->
        Logger.error(
          "Can't delete the subscription for: #{inspect(sign_up_trial)}, reason: #{inspect(other)}"
        )
    end
  end

  def update_trial(sign_up_trial, params) do
    sign_up_trial |> changeset(params) |> Repo.update()
  end

  defp get_trialing_subscription(stripe_subscription_id) do
    Subscription.by_stripe_id(stripe_subscription_id)
    |> case do
      %Subscription{status: :trialing} = subscription ->
        {:ok, subscription}

      _ ->
        {:error, :no_trialing_subscription}
    end
  end

  defp get_trial_with_not_sent_email(subscription) do
    by_subscription_id(subscription.id)
    |> case do
      %__MODULE__{sent_trial_will_end_email: false} = sign_up_trial ->
        {:ok, sign_up_trial}

      _ ->
        {:error, :no_sign_up_trial}
    end
  end

  defp create_promo_trial(%__MODULE__{user_id: user_id} = sign_up_trial) do
    user = Repo.get(User, user_id)

    PromoTrial.create_promo_trial(%{
      user_id: user_id,
      plans: @free_trial_plans,
      trial_days: @free_trial_days
    })
    |> case do
      {:ok, _} ->
        current_subscription = Subscription.current_subscription(user, Product.product_sanbase())
        update_trial(sign_up_trial, %{subscription_id: current_subscription.id})

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_send_email(sign_up_trial, email_type)
       when email_type in [
              :sent_first_education_email,
              :sent_second_education_email
            ] do
    do_send_email_and_mark_sent(sign_up_trial, email_type)
  end

  defp do_send_email_and_mark_sent(%__MODULE__{user_id: user_id} = sign_up_trial, email_type) do
    user = Repo.get(User, user_id)
    user_unique_str = User.get_unique_str(user)

    template = @templates[email_type]

    # User exists, we have proper template in Mandrill and this email type is not already sent
    if user && template && !Map.get(sign_up_trial, email_type) do
      Logger.info(
        "Trial email template #{template} sent to: #{user.email}, name=#{user_unique_str}"
      )

      Sanbase.MandrillApi.send(template, user.email, %{name: user_unique_str})

      update_trial(sign_up_trial, %{email_type => true})
    end
  end

  # Send email and delete subscription if user plan is one of our free trial plans
  defp maybe_send_email_and_delete_subscription(%Subscription{plan_id: plan_id} = subscription)
       when plan_id in @free_trial_plans do
    if by_subscription_id(subscription.id) do
      Logger.info(
        "Deleting subscription with id: #{subscription.stripe_id} for user: #{
          subscription.user_id
        }"
      )

      StripeApi.delete_subscription(subscription.stripe_id)

      maybe_send_trial_finished_email(subscription)
    end
  end

  defp maybe_send_email_and_delete_subscription(subscription) do
    Logger.info("Deleting subscription with id: #{subscription.stripe_id}")

    StripeApi.delete_subscription(subscription.stripe_id)
  end

  defp calc_trial_day(%__MODULE__{inserted_at: inserted_at}) do
    Timex.diff(Timex.now(), inserted_at, :days)
  end
end
