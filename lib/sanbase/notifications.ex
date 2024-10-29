defmodule Sanbase.Notifications do
  @moduledoc """
  The Notifications context.
  """

  import Ecto.Query, warn: false
  alias Sanbase.Repo

  alias Sanbase.Notifications.NotificationAction

  @doc """
  Returns the list of notification_actions.

  ## Examples

      iex> list_notification_actions()
      [%NotificationAction{}, ...]

  """
  def list_notification_actions do
    Repo.all(NotificationAction)
  end

  @doc """
  Gets a single notification_action.

  Raises `Ecto.NoResultsError` if the Notification action does not exist.

  ## Examples

      iex> get_notification_action!(123)
      %NotificationAction{}

      iex> get_notification_action!(456)
      ** (Ecto.NoResultsError)

  """
  def get_notification_action!(id), do: Repo.get!(NotificationAction, id)

  @doc """
  Creates a notification_action.

  ## Examples

      iex> create_notification_action(%{field: value})
      {:ok, %NotificationAction{}}

      iex> create_notification_action(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_notification_action(attrs \\ %{}) do
    %NotificationAction{}
    |> NotificationAction.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a notification_action.

  ## Examples

      iex> update_notification_action(notification_action, %{field: new_value})
      {:ok, %NotificationAction{}}

      iex> update_notification_action(notification_action, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_notification_action(%NotificationAction{} = notification_action, attrs) do
    notification_action
    |> NotificationAction.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a notification_action.

  ## Examples

      iex> delete_notification_action(notification_action)
      {:ok, %NotificationAction{}}

      iex> delete_notification_action(notification_action)
      {:error, %Ecto.Changeset{}}

  """
  def delete_notification_action(%NotificationAction{} = notification_action) do
    Repo.delete(notification_action)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking notification_action changes.

  ## Examples

      iex> change_notification_action(notification_action)
      %Ecto.Changeset{data: %NotificationAction{}}

  """
  def change_notification_action(%NotificationAction{} = notification_action, attrs \\ %{}) do
    NotificationAction.changeset(notification_action, attrs)
  end

  alias Sanbase.Notifications.Notification

  @doc """
  Returns the list of notifications.

  ## Examples

      iex> list_notifications()
      [%Notification{}, ...]

  """
  def list_notifications do
    Repo.all(Notification)
  end

  @doc """
  Gets a single notification.

  Raises `Ecto.NoResultsError` if the Notification does not exist.

  ## Examples

      iex> get_notification!(123)
      %Notification{}

      iex> get_notification!(456)
      ** (Ecto.NoResultsError)

  """
  def get_notification!(id), do: Repo.get!(Notification, id)

  @doc """
  Creates a notification.

  ## Examples

      iex> create_notification(%{field: value})
      {:ok, %Notification{}}

      iex> create_notification(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_notification(attrs \\ %{}) do
    %Notification{}
    |> Notification.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, notification} ->
        {:ok, Repo.preload(notification, :notification_action)}

      error ->
        error
    end
  end

  @doc """
  Updates a notification.

  ## Examples

      iex> update_notification(notification, %{field: new_value})
      {:ok, %Notification{}}

      iex> update_notification(notification, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_notification(%Notification{} = notification, attrs) do
    notification
    |> Notification.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a notification.

  ## Examples

      iex> delete_notification(notification)
      {:ok, %Notification{}}

      iex> delete_notification(notification)
      {:error, %Ecto.Changeset{}}

  """
  def delete_notification(%Notification{} = notification) do
    Repo.delete(notification)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking notification changes.

  ## Examples

      iex> change_notification(notification)
      %Ecto.Changeset{data: %Notification{}}

  """
  def change_notification(%Notification{} = notification, attrs \\ %{}) do
    Notification.changeset(notification, attrs)
  end

  alias Sanbase.Notifications.NotificationTemplate

  @doc """
  Returns the list of notification_templates.

  ## Examples

      iex> list_notification_templates()
      [%NotificationTemplate{}, ...]

  """
  def list_notification_templates do
    Repo.all(NotificationTemplate)
  end

  @doc """
  Gets a single notification_template.

  Raises `Ecto.NoResultsError` if the Notification template does not exist.

  ## Examples

      iex> get_notification_template!(123)
      %NotificationTemplate{}

      iex> get_notification_template!(456)
      ** (Ecto.NoResultsError)

  """
  def get_notification_template!(id), do: Repo.get!(NotificationTemplate, id)

  @doc """
  Creates a notification_template.

  ## Examples

      iex> create_notification_template(%{field: value})
      {:ok, %NotificationTemplate{}}

      iex> create_notification_template(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_notification_template(attrs \\ %{}) do
    %NotificationTemplate{}
    |> NotificationTemplate.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a notification_template.

  ## Examples

      iex> update_notification_template(notification_template, %{field: new_value})
      {:ok, %NotificationTemplate{}}

      iex> update_notification_template(notification_template, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_notification_template(%NotificationTemplate{} = notification_template, attrs) do
    notification_template
    |> NotificationTemplate.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a notification_template.

  ## Examples

      iex> delete_notification_template(notification_template)
      {:ok, %NotificationTemplate{}}

      iex> delete_notification_template(notification_template)
      {:error, %Ecto.Changeset{}}

  """
  def delete_notification_template(%NotificationTemplate{} = notification_template) do
    Repo.delete(notification_template)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking notification_template changes.

  ## Examples

      iex> change_notification_template(notification_template)
      %Ecto.Changeset{data: %NotificationTemplate{}}

  """
  def change_notification_template(%NotificationTemplate{} = notification_template, attrs \\ %{}) do
    NotificationTemplate.changeset(notification_template, attrs)
  end

  @doc """
  Gets a template for specific action_type, step, and channel.
  If no channel-specific template is found, falls back to "all" channel template.
  """
  def get_template(action_type, step, channel \\ "all") do
    # fetch by specific channel
    case Repo.get_by(NotificationTemplate,
           action_type: action_type,
           step: step,
           channel: channel
         ) do
      nil ->
        Repo.get_by(NotificationTemplate,
          action_type: action_type,
          step: step,
          channel: "all"
        )

      template ->
        template
    end
  end
end
