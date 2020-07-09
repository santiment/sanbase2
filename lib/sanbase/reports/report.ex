defmodule Sanbase.Report do
  @moduledoc """
  Module that manages .pdf file reports.
  Files are saved in s3 and the url is stored in database.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  require Logger

  alias Sanbase.Repo
  alias Sanbase.FileStore
  alias Sanbase.Utils.FileHash

  schema "reports" do
    field(:name, :string, null: false)
    field(:description, :string, null: true)
    field(:url, :string, null: false)
    field(:is_pro, :boolean, default: false)
    field(:is_published, :boolean, default: false)

    timestamps()
  end

  @doc false
  def changeset(report, attrs) do
    report
    |> cast(attrs, [:name, :description, :url, :is_published, :is_pro])
    |> validate_required([:url, :name, :is_published, :is_pro])
  end

  def create(params) do
    %__MODULE__{}
    |> changeset(params)
    |> Repo.insert()
  end

  def update(report, params) do
    report
    |> changeset(params)
    |> Repo.update()
  end

  def delete(report) do
    report |> Repo.delete()
  end

  def save_report(%Plug.Upload{filename: filename} = report, params) do
    %{report | filename: milliseconds_str() <> "_" <> filename}
    |> do_save_report(params)
  end

  def by_id(id) do
    Repo.get(__MODULE__, id)
  end

  def list_reports() do
    Repo.all(__MODULE__)
  end

  def get_published_reports(nil) do
    from(r in __MODULE__, where: r.is_published == true and r.is_pro == false)
    |> Repo.all()
  end

  def get_published_reports(%{plan: %{name: "FREE"}}) do
    from(r in __MODULE__, where: r.is_published == true and r.is_pro == false)
    |> Repo.all()
  end

  def get_published_reports(%{plan: %{name: "PRO"}}) do
    from(r in __MODULE__, where: r.is_published == true)
    |> Repo.all()
  end

  # Helpers

  defp do_save_report(%{filename: filename, path: filepath} = report, params) do
    with {:ok, content_hash} <- FileHash.calculate(filepath),
         {:ok, local_filepath} <- FileStore.store({report, content_hash}),
         file_url <- FileStore.url({local_filepath, content_hash}),
         {:ok, report} <- Map.merge(params, %{url: file_url}) |> create() do
      {:ok, report}
    else
      {:error, reason} ->
        Logger.error("Could not save file: #{filename}. Reason: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp milliseconds_str() do
    DateTime.utc_now()
    |> DateTime.to_unix(:millisecond)
    |> Integer.to_string()
  end
end
