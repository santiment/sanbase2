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
    field(:name, :string, null: true)
    field(:description, :string, null: true)
    field(:is_pro, :boolean, default: false)
    field(:is_published, :boolean, default: false)
    field(:url, :string)

    timestamps()
  end

  @doc false
  def changeset(report, attrs) do
    report
    |> cast(attrs, [:name, :description, :url, :is_published, :is_pro])
    |> validate_required([:url, :is_published, :is_pro])
  end

  def save(params) do
    %__MODULE__{}
    |> changeset(params)
    |> Repo.insert()
  end

  def save_report(%Plug.Upload{filename: filename} = report) do
    %{report | filename: milliseconds_str() <> "_" <> filename}
    |> do_save_report()
  end

  def list_published_reports(nil) do
    from(r in __MODULE__, where: r.is_published == true and r.is_pro == false)
    |> Repo.all()
  end

  def list_published_reports(%{plan: %{name: "FREE"}}) do
    from(r in __MODULE__, where: r.is_published == true and r.is_pro == false)
    |> Repo.all()
  end

  def list_published_reports(%{plan: %{name: "PRO"}}) do
    from(r in __MODULE__, where: r.is_published == true)
    |> Repo.all()
  end

  # Helpers

  defp do_save_report(%{filename: filename, path: filepath} = report) do
    with {:ok, content_hash} <- FileHash.calculate(filepath),
         {:ok, local_filepath} <- FileStore.store({report, content_hash}),
         file_url <- FileStore.url({local_filepath, content_hash}),
         {:ok, report} <- save(%{url: file_url}) do
      {:ok, report.url}
    else
      {:error, reason} ->
        Logger.error("Could not save file: #{filename}. Reason: #{inspect(reason)}")
        {:error, "Could not save file: #{filename}."}
    end
  end

  defp milliseconds_str() do
    DateTime.utc_now()
    |> DateTime.to_unix(:millisecond)
    |> Integer.to_string()
  end
end
