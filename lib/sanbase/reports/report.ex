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
    field(:tags, {:array, :string}, default: [])

    timestamps()
  end

  @doc false
  def new_changeset(report, attrs \\ %{}) do
    attrs = normalize_tags(attrs)

    report
    |> cast(attrs, [:name, :description, :url, :is_published, :is_pro, :tags])
  end

  def changeset(report, attrs) do
    attrs = normalize_tags(attrs)

    report
    |> cast(attrs, [:name, :description, :url, :is_published, :is_pro, :tags])
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

  def get_by_tags(tags, subscription) do
    __MODULE__
    |> get_by_tags_query(tags)
    |> get_published_reports_query(subscription)
    |> Repo.all()
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

  def get_published_reports(subscription) do
    __MODULE__
    |> get_published_reports_query(subscription)
    |> Repo.all()
  end

  # Helpers

  defp normalize_tags(%{"tags" => tags} = attrs) when is_binary(tags) do
    Map.put(attrs, "tags", String.split(tags, ~r{\s*,\s*}) |> Enum.map(&String.downcase/1))
  end

  defp normalize_tags(%{"tags" => tags} = attrs) when is_list(tags) do
    Map.put(attrs, "tags", Enum.map(tags, &String.downcase/1))
  end

  defp normalize_tags(%{tags: tags} = attrs) when is_binary(tags) do
    Map.put(attrs, :tags, String.split(tags, ~r{\s*,\s*}) |> Enum.map(&String.downcase/1))
  end

  defp normalize_tags(%{tags: tags} = attrs) when is_list(tags) do
    Map.put(attrs, :tags, Enum.map(tags, &String.downcase/1))
  end

  defp normalize_tags(attrs), do: attrs

  defp get_by_tags_query(query, tags) do
    from(r in query, where: fragment("select ? && ?", r.tags, ^tags))
  end

  defp get_published_reports_query(query, nil) do
    from(r in query, where: r.is_published == true and r.is_pro == false)
  end

  defp get_published_reports_query(query, %{plan: %{name: "FREE"}}) do
    from(r in query, where: r.is_published == true and r.is_pro == false)
  end

  defp get_published_reports_query(query, %{plan: %{name: "PRO"}}) do
    from(r in query, where: r.is_published == true)
  end

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
