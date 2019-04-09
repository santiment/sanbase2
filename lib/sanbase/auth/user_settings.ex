defmodule Sanbase.Auth.UserSettings do
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__
  alias Sanbase.Auth.{User, Settings}
  alias Sanbase.Repo

  schema "user_settings" do
    belongs_to(:user, User)
    embeds_one(:settings, Settings, on_replace: :update)

    timestamps()
  end

  def changeset(%UserSettings{} = user_settings, attrs \\ %{}) do
    user_settings
    |> cast(attrs, [:user_id])
    |> cast_embed(:settings, required: true, with: &Settings.changeset/2)
    |> validate_required([:user_id])
    |> unique_constraint(:user_id)
  end

  def settings_for(%User{id: user_id}) do
    Repo.get_by(UserSettings, user_id: user_id)
    |> case do
      nil ->
        changeset(%UserSettings{}, %{user_id: user_id, settings: %{}})
        |> Repo.insert!()
        |> modify_settings()

      %UserSettings{} = us ->
        modify_settings(us)
    end
  end

  def toggle_notification_channel(%User{id: user_id}, params) do
    settings_update(user_id, params)
  end

  def set_telegram_chat_id(user_id, chat_id) do
    settings_update(user_id, %{telegram_chat_id: chat_id})
  end

  def change_newsletter_subscription(%User{id: user_id}, params) do
    settings_update(user_id, params)
  end

  defp settings_update(user_id, params) do
    Repo.get_by(UserSettings, user_id: user_id)
    |> case do
      nil ->
        changeset(%UserSettings{}, %{user_id: user_id, settings: params})

      %UserSettings{} = us ->
        changeset(us, %{settings: params})
    end
    |> Repo.insert_or_update()
    |> case do
      {:ok, %UserSettings{} = us} ->
        {:ok, %{us | settings: modify_settings(us)}}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp modify_settings(%UserSettings{} = us) do
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
