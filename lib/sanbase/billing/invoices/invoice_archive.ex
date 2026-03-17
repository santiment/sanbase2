defmodule Sanbase.Billing.Invoices.InvoiceArchive do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo

  schema "invoice_archives" do
    field(:year, :integer)
    field(:month, :integer)
    field(:status, :string, default: "pending")
    field(:s3_key, :string)
    field(:invoice_count, :integer, default: 0)
    field(:total_amount, :integer, default: 0)
    field(:file_size, :integer)
    field(:error_message, :string)

    belongs_to(:user, Sanbase.Accounts.User, foreign_key: :generated_by)

    timestamps()
  end

  @fields [
    :year,
    :month,
    :status,
    :s3_key,
    :invoice_count,
    :total_amount,
    :file_size,
    :error_message,
    :generated_by
  ]

  def changeset(archive, attrs) do
    archive
    |> cast(attrs, @fields)
    |> validate_required([:year, :month])
    |> unique_constraint([:year, :month])
  end

  def list_all do
    from(a in __MODULE__, order_by: [desc: a.year, desc: a.month])
    |> Repo.all()
  end

  def get_by_month(year, month) do
    Repo.get_by(__MODULE__, year: year, month: month)
  end

  def create_or_update(attrs) do
    case get_by_month(attrs[:year] || attrs["year"], attrs[:month] || attrs["month"]) do
      nil -> %__MODULE__{}
      existing -> existing
    end
    |> changeset(attrs)
    |> Repo.insert_or_update()
  end

  def mark_completed(archive, attrs) do
    archive
    |> changeset(Map.merge(attrs, %{status: "completed"}))
    |> Repo.update()
  end

  def mark_failed(archive, error_message) do
    archive
    |> changeset(%{status: "failed", error_message: error_message})
    |> Repo.update()
  end

  def delete!(archive) do
    Repo.delete!(archive)
  end
end
