defmodule Sanbase.Billing.InvoiceMirror.SyncRun do
  @moduledoc ~s"""
  A record of one import of invoices from Stripe.

  Kept so that a range nobody has imported is visibly missing rather than looking like
  a range without revenue.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo

  schema "stripe_invoice_sync_runs" do
    field(:from_date, :date)
    field(:to_date, :date)
    field(:status, :string, default: "running")
    field(:invoices_upserted, :integer, default: 0)
    field(:lines_upserted, :integer, default: 0)
    field(:duration_ms, :integer)
    field(:error_message, :string)

    belongs_to(:user, Sanbase.Accounts.User, foreign_key: :triggered_by)

    timestamps(type: :utc_datetime)
  end

  @fields ~w(from_date to_date status invoices_upserted lines_upserted duration_ms
             error_message triggered_by)a

  def changeset(run, attrs) do
    run
    |> cast(attrs, @fields)
    |> validate_required([:from_date, :to_date, :status])
  end

  def create(attrs) do
    %__MODULE__{} |> changeset(attrs) |> Repo.insert()
  end

  def update(%__MODULE__{} = run, attrs) do
    run |> changeset(attrs) |> Repo.update()
  end

  @doc ~s"""
  Marks the run failed with `message`, unless it has finished in the meantime.
  """
  def interrupt(run_id, message) do
    from(r in __MODULE__, where: r.id == ^run_id and r.status == "running")
    |> Repo.update_all(set: [status: "failed", error_message: message, updated_at: now()])
  end

  @doc ~s"""
  Marks failed every run still running `hours` after it started: a node restarted or
  died under it, and it would otherwise show as running forever.
  """
  def interrupt_stale(hours) do
    cutoff = DateTime.add(now(), -hours, :hour)

    from(r in __MODULE__, where: r.status == "running" and r.inserted_at < ^cutoff)
    |> Repo.update_all(set: [status: "failed", error_message: "interrupted", updated_at: now()])
  end

  @doc ~s"""
  The most recent runs, newest first.
  """
  def recent(limit \\ 10) do
    from(r in __MODULE__, order_by: [desc: r.id], limit: ^limit)
    |> Repo.all()
  end

  @doc ~s"""
  The last run that completed, or `nil` when nothing has ever been imported.
  """
  def last_completed do
    from(r in __MODULE__, where: r.status == "completed", order_by: [desc: r.id], limit: 1)
    |> Repo.one()
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
