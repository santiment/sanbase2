defmodule Sanbase.Billing.BusinessClients do
  @moduledoc ~s"""
  Business clients: who they are, what they pay, whether they churned or renewed, and
  what people logged about them. Backs the Business Clients admin page.

  Revenue, churn and renewal are derived from the invoice mirror in
  `Sanbase.Billing.InvoiceMirror`, which holds every Stripe invoice whatever paid it.
  The formulas live in `Sanbase.Billing.BusinessClients.Report`; their parameters are
  editable in `Sanbase.Billing.BusinessClients.Settings`.

  A client is one user account. A user is a business client while a paid invoice line
  of a business plan covers the date, or of a business-email plan when their email is
  not a free provider (or an admin override says so).
  """

  import Ecto.Query

  alias Sanbase.Billing.BusinessClients.{LogEntry, Override, Report, Settings}
  alias Sanbase.Repo

  # ─── Report ──────────────────────────────────────────────────────────────

  defdelegate page(opts \\ []), to: Report
  defdelegate list_clients(opts \\ []), to: Report
  defdelegate metrics(opts \\ []), to: Report
  defdelegate monthly_metrics(opts \\ []), to: Report
  defdelegate client_detail(user_id), to: Report
  defdelegate business_email_users(), to: Report
  defdelegate formula_notes(settings), to: Report

  # ─── Settings ────────────────────────────────────────────────────────────

  defdelegate settings(), to: Settings, as: :get
  defdelegate update_settings(attrs, updated_by_id), to: Settings, as: :update

  # ─── Log entries ─────────────────────────────────────────────────────────

  @doc ~s"""
  Every log entry of a user, newest first, with author and resolver preloaded.
  """
  @spec list_entries(integer()) :: [%LogEntry{}]
  def list_entries(user_id) do
    from(e in LogEntry,
      where: e.user_id == ^user_id,
      order_by: [desc: e.inserted_at, desc: e.id],
      preload: [:author, :resolved_by]
    )
    |> Repo.all()
  end

  @spec change_entry(map()) :: Ecto.Changeset.t()
  def change_entry(attrs \\ %{}) do
    LogEntry.create_changeset(%LogEntry{}, attrs, Settings.get())
  end

  @spec create_entry(integer(), integer(), map()) ::
          {:ok, %LogEntry{}} | {:error, Ecto.Changeset.t()}
  def create_entry(user_id, author_id, attrs) do
    %LogEntry{user_id: user_id, author_id: author_id}
    |> LogEntry.create_changeset(attrs, Settings.get())
    |> Repo.insert()
  end

  @spec resolve_entry(integer(), integer()) ::
          {:ok, %LogEntry{}} | {:error, :not_found | Ecto.Changeset.t()}
  def resolve_entry(entry_id, resolved_by_id) do
    case Repo.get(LogEntry, entry_id) do
      nil -> {:error, :not_found}
      %LogEntry{resolved_at: %DateTime{}} = entry -> {:ok, entry}
      entry -> entry |> LogEntry.resolve_changeset(resolved_by_id) |> Repo.update()
    end
  end

  @doc ~s"""
  The manual status from open entries: the most severe one wins, `:healthy` when none.
  """
  @spec manual_status([%LogEntry{}]) :: :healthy | :at_risk | :high_risk
  def manual_status(open_entries) do
    severities = MapSet.new(open_entries, & &1.severity)

    cond do
      MapSet.member?(severities, "high_risk") -> :high_risk
      MapSet.member?(severities, "at_risk") -> :at_risk
      true -> :healthy
    end
  end

  # ─── Overrides ───────────────────────────────────────────────────────────

  @doc ~s"""
  The business yes/no overrides, as a map of user id to boolean.
  """
  @spec overrides() :: %{integer() => boolean()}
  def overrides do
    from(o in Override, select: {o.user_id, o.business})
    |> Repo.all()
    |> Map.new()
  end

  @spec set_override(integer(), boolean(), integer(), String.t() | nil) ::
          {:ok, %Override{}} | {:error, Ecto.Changeset.t()}
  def set_override(user_id, business?, set_by_id, note \\ nil) do
    (Repo.get_by(Override, user_id: user_id) ||
       %Override{user_id: user_id})
    |> Map.put(:set_by_id, set_by_id)
    |> Override.changeset(%{business: business?, note: note})
    |> Repo.insert_or_update()
  end

  @spec clear_override(integer()) :: :ok
  def clear_override(user_id) do
    from(o in Override, where: o.user_id == ^user_id) |> Repo.delete_all()
    :ok
  end

  # ─── Email ───────────────────────────────────────────────────────────────

  @doc ~s"""
  Whether an email belongs to a business domain - anything not on the free provider
  list. `nil` and malformed emails are not business.
  """
  @spec business_email?(String.t() | nil, [String.t()]) :: boolean()
  def business_email?(email, free_domains) when is_binary(email) do
    case String.split(String.downcase(String.trim(email)), "@") do
      [_local, domain] when domain != "" ->
        domain not in Enum.map(free_domains, &String.downcase/1)

      _ ->
        false
    end
  end

  def business_email?(_email, _free_domains), do: false
end
