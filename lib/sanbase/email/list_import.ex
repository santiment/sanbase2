defmodule Sanbase.Email.ListImport do
  @moduledoc """
  One-time import of a list's subscriptions from Mailjet into Sanbase.

  Mailjet is the source of truth: users whose email receives the list's
  campaigns get the list setting turned on, and all other users get it turned
  off. Every change is recorded as a consent with the `:mailjet_list_import`
  source. Mailjet is not called and no email is sent. The marketing consent
  (`users.marketing_accepted`) is not changed.

  Run it with the default `dry_run: true` first to see what would change:

      Sanbase.Email.ListImport.import_from_mailjet(:newsletter)
      Sanbase.Email.ListImport.import_from_mailjet(:newsletter, dry_run: false)
  """

  import Ecto.Query, only: [from: 2]

  require Logger

  alias Sanbase.Accounts.{User, UserSettings}
  alias Sanbase.Email.{Lists, ListSubscription, MailjetApi}
  alias Sanbase.Repo

  @spec import_from_mailjet(Lists.list_key(), keyword()) :: {:ok, map()} | {:error, term()}
  def import_from_mailjet(list_key, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, true)
    list = Lists.get!(list_key)

    with {:ok, emails} <- MailjetApi.client().fetch_list_subscribed_emails(list.mailjet_list),
         {:ok, subscribed} <- non_empty(emails) do
      changes = users_to_change(list, subscribed)

      summary = %{
        dry_run: dry_run,
        mailjet_subscribed: MapSet.size(subscribed),
        to_subscribe: Enum.count(changes, fn {_user_id, value} -> value end),
        to_unsubscribe: Enum.count(changes, fn {_user_id, value} -> not value end)
      }

      if dry_run,
        do: {:ok, summary},
        else: {:ok, Map.put(summary, :failed, apply_changes(list_key, changes))}
    end
  end

  # An empty list most likely means a wrong list id or a failed fetch. Importing
  # it would unsubscribe every user, so refuse.
  defp non_empty([]), do: {:error, :empty_mailjet_list}
  defp non_empty(emails), do: {:ok, MapSet.new(emails, &String.downcase/1)}

  # Returns {user_id, subscribed} for the users whose setting differs from Mailjet.
  defp users_to_change(list, subscribed) do
    setting = Atom.to_string(list.setting)

    from(u in User,
      left_join: us in UserSettings,
      on: us.user_id == u.id,
      where: not is_nil(u.email),
      select: {u.id, u.email, fragment("(?->>?)::boolean", us.settings, ^setting)}
    )
    |> Repo.all()
    |> Enum.flat_map(fn {user_id, email, current} ->
      current = if is_nil(current), do: list.default, else: current
      target = MapSet.member?(subscribed, String.downcase(email))

      if target != current, do: [{user_id, target}], else: []
    end)
  end

  defp apply_changes(list_key, changes) do
    changes
    |> Enum.reject(fn {user_id, value} ->
      case ListSubscription.set(user_id, list_key, value, :mailjet_list_import,
             notify_mailjet: false
           ) do
        {:ok, _changed?} ->
          true

        {:error, error} ->
          Logger.error(
            "Failed to import the #{list_key} list for user #{user_id}: #{inspect(error)}"
          )

          false
      end
    end)
    |> Enum.map(fn {user_id, _value} -> user_id end)
  end
end
