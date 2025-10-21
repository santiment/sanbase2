defmodule Sanbase.Email.DevConsole do
  require Logger

  alias Sanbase.Repo
  alias Sanbase.Accounts.User
  alias Sanbase.TemplateMailer
  alias Sanbase.Email.Template

  @doc """
  Preview the comment notification email data that would be sent to a user.

  Returns the exact map/JSON that will be sent to the "notification" email template.
  No database writes are performed. This is useful for testing what the email would look like.

  ## Parameters
    - user_identifier: User email (string) or user ID (integer)

  ## Returns
    {:ok, notification_data_map} with the variables that would be sent to the template
    {:error, reason} if user not found or no notification data exists
  """
  def preview_comment_notification_email(user_identifier) when is_binary(user_identifier) do
    notifications_map = Sanbase.Comments.Notification.notify_users_map()

    case notifications_map[user_identifier] do
      nil -> {:error, "No notification data found for email #{user_identifier}"}
      data -> {:ok, data}
    end
  end

  def preview_comment_notification_email(user_id) when is_integer(user_id) do
    user = Repo.get(User, user_id)

    case user do
      nil ->
        {:error, "User with ID #{user_id} not found"}

      user ->
        preview_comment_notification_email(user.email)
    end
  end

  @doc """
  Send the comment notification email to a specified recipient email address.

  Generates the comment notification email for a user but sends it to an override email.
  This bypasses validation checks and email exclusion lists, useful for testing on production.
  No database writes are performed - only queries existing data and sends the email.

  ## Parameters
    - recipient_email: Email address to send to (override destination)
    - user_identifier: User email (string) or ID (integer) whose notification data to use

  ## Returns
    The result of the email send operation (typically {:ok, metadata} or {:error, reason})

  ## Example
    iex> Sanbase.Email.DevConsole.send_comment_notification_to_email("test@example.com", 123)
    {:ok, ...}

    iex> Sanbase.Email.DevConsole.send_comment_notification_to_email("test@example.com", "user@example.com")
    {:ok, ...}
  """
  def send_comment_notification_to_email(recipient_email, user_identifier)
      when is_binary(recipient_email) do
    case preview_comment_notification_email(user_identifier) do
      {:error, reason} ->
        {:error, reason}

      {:ok, notification_data} ->
        Logger.info(
          "Sending comment notification preview email to #{recipient_email} with template: notification"
        )

        TemplateMailer.send(
          recipient_email,
          Template.comment_notification_template(),
          notification_data
        )
    end
  end
end
