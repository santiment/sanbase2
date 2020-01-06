defmodule Sanbase.Auth.UserSettings do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Auth.{User, Settings}
  alias Sanbase.Repo

  schema "user_settings" do
    belongs_to(:user, User)
    embeds_one(:settings, Settings, on_replace: :update)

    timestamps()
  end

  def changeset(%__MODULE__{} = user_settings, attrs \\ %{}) do
    user_settings
    |> cast(attrs, [:user_id])
    |> cast_embed(:settings, required: true, with: &Settings.changeset/2)
    |> validate_required([:user_id])
    |> unique_constraint(:user_id)
  end

  def settings_for(%User{user_settings: %{settings: %Settings{} = settings}}) do
    settings
  end

  def settings_for(%User{id: user_id}) do
    Repo.get_by(__MODULE__, user_id: user_id)
    |> case do
      nil ->
        changeset(%__MODULE__{}, %{user_id: user_id, settings: %{}})
        |> Repo.insert!()
        |> modify_settings()

      %__MODULE__{} = us ->
        modify_settings(us)
    end
  end

  def update_settings(%User{id: id}, params) do
    settings_update(id, params)
  end

  def toggle_notification_channel(%User{id: user_id}, params) do
    settings_update(user_id, params)
  end

  def set_telegram_chat_id(user_id, chat_id) do
    settings_update(user_id, %{telegram_chat_id: chat_id})
  end

  def change_newsletter_subscription(%User{id: user_id, email: nil}, params) do
    settings_update(user_id, params)
  end

  def change_newsletter_subscription(%User{id: user_id, email: email}, params) do
    settings_update(user_id, params)
    |> case do
      {:ok, %{settings: %{newsletter_subscription: :off}}} = response ->
        Sanbase.Email.Mailchimp.unsubscribe_email(email)
        response

      {:ok, %{settings: %{newsletter_subscription: :weekly}}} = response ->
        Sanbase.Email.Mailchimp.subscribe_email(email)
        response

      {:ok, %{settings: %{newsletter_subscription: :daily}}} = response ->
        Sanbase.Email.Mailchimp.subscribe_email(email)
        response

      response ->
        response
    end
  end

  defp settings_update(user_id, params) do
    Repo.get_by(__MODULE__, user_id: user_id)
    |> case do
      nil ->
        changeset(%__MODULE__{}, %{user_id: user_id, settings: params})

      %__MODULE__{} = us ->
        changeset(us, %{settings: params})
    end
    |> Repo.insert_or_update()
    |> case do
      {:ok, %__MODULE__{} = us} ->
        {:ok, %{us | settings: modify_settings(us)}}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp modify_settings(%__MODULE__{} = us) do
    %{
      us.settings
      | has_telegram_connected: us.settings.telegram_chat_id != nil,
        newsletter_subscription:
          us.settings.newsletter_subscription
          |> String.downcase()
          |> String.to_existing_atom()
    }
  end
end
