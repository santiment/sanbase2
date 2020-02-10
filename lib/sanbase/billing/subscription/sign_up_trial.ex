defmodule Sanbase.Billing.Subscription.SignUpTrial do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  require Logger

  alias Sanbase.Auth.User
  alias Sanbase.Billing.Subscription.PromoTrial
  alias Sanbase.Repo

  @free_trial_days 14
  # Free trial plans are Sanbase PRO plans
  @free_trial_plans [13]

  @day_email_type_map %{
    3 => :sent_3day_email,
    11 => :sent_11day_email,
    14 => :sent_end_trial_email
  }

  @templates %{
    sent_welcome_email: "welcome_email"
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
    PromoTrial.create_promo_trial(%{
      user_id: user_id,
      plans: @free_trial_plans,
      trial_days: @free_trial_days
    })
    |> case do
      {:ok, subscriptions} ->
        send_email_async(user_id, :sent_welcome_email)

        {:ok, subscriptions}

      {:error, error} ->
        {:error, error}
    end
  end

  def send_email_async(user_id, email_type) when is_integer(user_id) do
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      send_email(user_id, email_type)
    end)
  end

  defp send_email(user_id, :sent_welcome_email = email_type) do
    {:ok, sign_up_trial} = create(user_id)

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

    Sanbase.MandrillApi.send(template, user.email, %{name: user.username || user.email})
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
