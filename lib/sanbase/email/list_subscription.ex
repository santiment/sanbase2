defmodule Sanbase.Email.ListSubscription do
  @moduledoc """
  The single place that changes a user's subscription to a list from
  `Sanbase.Email.Lists`.

  A change writes every place that holds the subscription (the list setting and
  its mirrored settings), records the consent with its source, and adds or
  removes the contact in Mailjet. Mailjet is called only when the subscription
  actually changes.
  """

  import Ecto.Query, only: [from: 2]

  alias Sanbase.Accounts.{User, UserSettings}
  alias Sanbase.Email.{Lists, ListConsent}
  alias Sanbase.Repo

  @doc """
  Set the user's subscription to the list and sync it to Mailjet.

  Returns `{:ok, changed?}`.

  ## Options

    - `:notify_mailjet` - call Mailjet when the subscription changes. Defaults
      to `true`. Pass `false` to bring Sanbase in line with Mailjet without
      calling it.
  """
  @spec set(non_neg_integer(), Lists.list_key(), boolean(), ListConsent.source(), keyword()) ::
          {:ok, boolean()} | {:error, term()}
  def set(user_id, list_key, subscribed, source, opts \\ []) when is_boolean(subscribed) do
    Repo.transaction(fn ->
      case change(user_id, list_key, subscribed, source) do
        {:ok, changed?} -> changed?
        {:error, error} -> Repo.rollback(error)
      end
    end)
    |> case do
      {:ok, changed?} ->
        if changed? and Keyword.get(opts, :notify_mailjet, true),
          do: notify_mailjet(user_id, list_key, subscribed)

        {:ok, changed?}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Write the subscription to the database without calling Mailjet.

  Meant to run inside a caller's transaction. When it returns `{:ok, true}`,
  the caller must call `notify_mailjet/3` after the transaction commits.
  """
  @spec change(non_neg_integer(), Lists.list_key(), boolean(), ListConsent.source()) ::
          {:ok, boolean()} | {:error, term()}
  def change(user_id, list_key, subscribed, source) when is_boolean(subscribed) do
    list = Lists.get!(list_key)
    settings = Map.new(Lists.settings_keys(list_key), &{&1, subscribed})

    with {:ok, previous} <- current_value(user_id, list),
         {:ok, _} <- UserSettings.put_list_settings(user_id, settings),
         :ok <-
           maybe_record_consent(previous != subscribed, user_id, list_key, subscribed, source) do
      {:ok, previous != subscribed}
    end
  end

  @doc "Add the user to or remove the user from the list in Mailjet."
  @spec notify_mailjet(non_neg_integer(), Lists.list_key(), boolean()) :: :ok
  def notify_mailjet(user_id, list_key, subscribed) do
    Sanbase.Email.MailjetEventEmitter.emit_event(
      {:ok, user_id},
      :email_list_subscription,
      %{list: list_key, subscribed: subscribed}
    )

    :ok
  end

  defp current_value(user_id, list) do
    # Lock the users row before the settings row, in the same order as
    # Sanbase.Accounts.UserSettings and Sanbase.Accounts, so concurrent changes
    # for the same user cannot deadlock.
    from(u in User, where: u.id == ^user_id, select: u.id, lock: "FOR UPDATE")
    |> Repo.one()
    |> case do
      nil ->
        {:error, :user_not_found}

      _ ->
        from(us in UserSettings,
          where: us.user_id == ^user_id,
          select: us.settings,
          lock: "FOR UPDATE"
        )
        |> Repo.one()
        |> case do
          nil -> {:ok, list.default}
          settings -> {:ok, Map.get(settings, list.setting) == true}
        end
    end
  end

  defp maybe_record_consent(false = _changed?, _user_id, _list_key, _subscribed, _source), do: :ok

  defp maybe_record_consent(true = _changed?, user_id, list_key, subscribed, source) do
    case Lists.get!(list_key).basis do
      :consent ->
        case ListConsent.create(user_id, list_key, subscribed, source) do
          {:ok, _} -> :ok
          {:error, error} -> {:error, error}
        end

      _ ->
        :ok
    end
  end
end
