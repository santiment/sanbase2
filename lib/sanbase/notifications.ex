defmodule Sanbase.Notifications do
  @moduledoc """
  The Notifications context.
  """

  import Ecto.Query, warn: false
  alias Sanbase.Repo

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
  Gets a template for specific action, step, and channel.
  If no channel-specific template is found, falls back to "all" channel template.
  """
  def get_template(action, step, channel \\ "all", mime_type \\ "text/plain") do
    query =
      from(nt in NotificationTemplate,
        where:
          nt.action == ^action and
            nt.step == ^step and
            nt.channel == ^channel and
            nt.mime_type == ^mime_type,
        limit: 1
      )

    case Repo.one(query) do
      nil ->
        # Try again with "all" channel
        fallback_query =
          from(nt in NotificationTemplate,
            where:
              nt.action == ^action and
                nt.step == ^step and
                nt.channel == "all" and
                nt.mime_type == ^mime_type,
            limit: 1
          )

        Repo.one(fallback_query)

      template ->
        template
    end
  end
end
