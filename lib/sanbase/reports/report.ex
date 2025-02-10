defmodule Sanbase.Report do
  @moduledoc """
  Module that manages .pdf file reports.
  Files are saved in s3 and the url is stored in database.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.FileStore
  alias Sanbase.Repo
  alias Sanbase.Utils.FileHash

  require Logger

  @type get_reports_opts :: %{
          required(:is_logged_in) => boolean(),
          optional(:plan_name) => String.t()
        }

  schema "reports" do
    field(:name, :string)
    field(:description, :string)
    field(:url, :string)
    field(:is_pro, :boolean, default: false)
    field(:is_published, :boolean, default: false)
    field(:tags, {:array, :string}, default: [])

    timestamps()
  end

  @doc false
  def new_changeset(report, attrs \\ %{}) do
    attrs = normalize_tags(attrs)

    cast(report, attrs, [:name, :description, :url, :is_published, :is_pro, :tags])
  end

  def changeset(report, attrs) do
    attrs = normalize_tags(attrs)

    report
    |> cast(attrs, [:name, :description, :url, :is_published, :is_pro, :tags])
    |> validate_required([:url, :name, :is_published, :is_pro])
  end

  def by_id(id) do
    Repo.get(__MODULE__, id)
  end

  def list_reports do
    Repo.all(__MODULE__)
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
    Repo.delete(report)
  end

  @spec get_published_reports(get_reports_opts()) :: list(%__MODULE__{})
  def get_published_reports(opts) do
    __MODULE__
    |> get_published_reports_query()
    |> Repo.all()
    |> show_only_preview_fields?(opts)
  end

  @spec get_by_tags(list(String.t()), get_reports_opts()) :: list(%__MODULE__{})
  def get_by_tags(tags, opts) do
    __MODULE__
    |> get_by_tags_query(tags)
    |> get_published_reports_query()
    |> Repo.all()
    |> show_only_preview_fields?(opts)
  end

  def save_report(%Plug.Upload{filename: filename} = report, params) do
    do_save_report(%{report | filename: milliseconds_str() <> "_" <> filename}, params)
  end

  # Helpers

  defp normalize_tags(%{"tags" => tags} = attrs) when is_binary(tags) do
    Map.put(attrs, "tags", tags |> String.split(~r{\s*,\s*}) |> Enum.map(&String.downcase/1))
  end

  defp normalize_tags(%{"tags" => tags} = attrs) when is_list(tags) do
    Map.put(attrs, "tags", Enum.map(tags, &String.downcase/1))
  end

  defp normalize_tags(%{tags: tags} = attrs) when is_binary(tags) do
    Map.put(attrs, :tags, tags |> String.split(~r{\s*,\s*}) |> Enum.map(&String.downcase/1))
  end

  defp normalize_tags(%{tags: tags} = attrs) when is_list(tags) do
    Map.put(attrs, :tags, Enum.map(tags, &String.downcase/1))
  end

  defp normalize_tags(attrs), do: attrs

  defp get_by_tags_query(query, tags) do
    from(r in query,
      where: fragment("select ? && ?", r.tags, ^tags),
      order_by: [desc: r.inserted_at, desc: r.id]
    )
  end

  defp get_published_reports_query(query) do
    from(r in query, where: r.is_published == true, order_by: [desc: r.inserted_at, desc: r.id])
  end

  defp show_only_preview_fields?(reports, %{is_logged_in: false}) do
    Enum.map(reports, fn report -> %{report | url: nil} end)
  end

  defp show_only_preview_fields?(reports, %{is_logged_in: true, plan_name: "FREE"}) do
    Enum.map(reports, fn
      %__MODULE__{is_pro: true} = report ->
        %{report | url: nil}

      %__MODULE__{is_pro: false} = report ->
        report
    end)
  end

  defp show_only_preview_fields?(reports, %{is_logged_in: true}) do
    reports
  end

  defp do_save_report(%{filename: filename, path: filepath} = report, params) do
    with {:ok, content_hash} <- FileHash.calculate(filepath),
         {:ok, local_filepath} <- FileStore.store({report, content_hash}),
         file_url = FileStore.url({local_filepath, content_hash}),
         {:ok, report} <- params |> Map.put(:url, file_url) |> create() do
      {:ok, report}
    else
      {:error, reason} ->
        Logger.error("Could not save file: #{filename}. Reason: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp milliseconds_str do
    DateTime.utc_now()
    |> DateTime.to_unix(:millisecond)
    |> Integer.to_string()
  end
end
