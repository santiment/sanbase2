defmodule Sanbase.Auth.UserSettings do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias __MODULE__
  alias Sanbase.Auth.User
  alias Sanbase.Repo

  schema "user_settings" do
    field(:signal_notify_email, :boolean, dafault: false)
    field(:signal_notify_telegram, :boolean, dafault: false)
    field(:telegram_url, :string)

    belongs_to(:user, User)

    timestamps()
  end

  def changeset(%UserSettings{} = user_settings, attrs \\ %{}) do
    user_settings
    |> cast(attrs, [:signal_notify_email, :signal_notify_telegram, :telegram_url, :user_id])
    |> validate_required([:user_id])
    |> unique_constraint(:user_id)
  end

  def settings_for(%User{id: user_id}) do
    Repo.get_by(UserSettings, user_id: user_id)
  end

  def toggle_notification_channel(%User{id: user_id}, channel) do
    Repo.get_by(UserSettings, user_id: user_id)
    |> case do
      %UserSettings{} = us ->
        changeset(us, %{channel => !(us |> Map.get(channel))})

      nil ->
        changeset(%UserSettings{}, %{channel => true, user_id: user_id})
    end
    |> Repo.insert_or_update()
  end

  def generate_telegram_url(%User{id: user_id} = user) do
    with %UserSettings{} = us <-
           Repo.get_by(UserSettings, user_id: user_id, signal_notify_telegram: true),
         {:ok, telegram_url} <- generate_telegram_url_int(user) do
      changeset(us, %{telegram_url: telegram_url})
      |> Repo.update()
    else
      nil ->
        {:error, "Telegram channel is not active!"}

      {:error, error} ->
        {:error, "Cannot generate telegram url!"}
    end
  end

  defp generate_telegram_url_int(%User{id: user_id} = user) do
    # for testing
    {:ok, "https://example.com"}
  end
end
