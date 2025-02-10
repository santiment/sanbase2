defmodule Sanbase.SheetsTemplate do
  @moduledoc """
  Module that SanSheets templates.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Repo

  require Logger

  schema "sheets_templates" do
    field(:name, :string)
    field(:description, :string)
    field(:url, :string)
    field(:is_pro, :boolean, default: false)

    timestamps()
  end

  @doc false
  def new_changeset(sheets_template, attrs \\ %{}) do
    cast(sheets_template, attrs, [:name, :description, :url, :is_pro])
  end

  def changeset(sheets_template, attrs) do
    sheets_template
    |> cast(attrs, [:name, :description, :url, :is_pro])
    |> validate_required([:url, :name, :is_pro])
  end

  def by_id(id) do
    Repo.get(__MODULE__, id)
  end

  def list do
    Repo.all(__MODULE__)
  end

  def create(params) do
    %__MODULE__{}
    |> changeset(params)
    |> Repo.insert()
  end

  def update(sheets_template, params) do
    sheets_template
    |> changeset(params)
    |> Repo.update()
  end

  def delete(sheets_template) do
    Repo.delete(sheets_template)
  end

  def get_all(opts) do
    show_only_preview_fields?(list(), opts)
  end

  # Helpers

  defp show_only_preview_fields?(sheets_templates, %{is_logged_in: false}) do
    Enum.map(sheets_templates, fn sheets_template -> %{sheets_template | url: nil} end)
  end

  defp show_only_preview_fields?(sheets_templates, %{is_logged_in: true, plan_name: "FREE"}) do
    Enum.map(sheets_templates, fn
      %__MODULE__{is_pro: true} = sheets_template ->
        %{sheets_template | url: nil}

      %__MODULE__{is_pro: false} = sheets_template ->
        sheets_template
    end)
  end

  defp show_only_preview_fields?(sheets_templates, %{is_logged_in: true, plan_name: plan}) when plan != "FREE" do
    sheets_templates
  end
end
