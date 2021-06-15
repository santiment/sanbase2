defmodule Sanbase.Webinar do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Repo

  schema "webinars" do
    field(:description, :string)
    field(:end_time, :utc_datetime)
    field(:image_url, :string)
    field(:is_pro, :boolean, default: false)
    field(:start_time, :utc_datetime)
    field(:title, :string)
    field(:url, :string)

    timestamps()
  end

  def new_changeset(webinar, attrs \\ %{}) do
    webinar
    |> cast(attrs, [:title, :description, :url, :image_url, :start_time, :end_time, :is_pro])
  end

  @doc false
  def changeset(webinar, attrs) do
    webinar
    |> cast(attrs, [:title, :description, :url, :image_url, :start_time, :end_time, :is_pro])
    |> validate_required([:title, :description, :url, :image_url, :start_time, :end_time, :is_pro])
  end

  def by_id(id) do
    Repo.get(__MODULE__, id)
  end

  def list() do
    Repo.all(__MODULE__)
  end

  def create(params) do
    %__MODULE__{}
    |> changeset(params)
    |> Repo.insert()
  end

  def update(webinar, params) do
    webinar
    |> changeset(params)
    |> Repo.update()
  end

  def delete(webinar) do
    webinar |> Repo.delete()
  end

  def get_all(opts) do
    list()
    |> show_only_preview_fields?(opts)
  end

  defp show_only_preview_fields?(webinars, %{is_logged_in: false}) do
    Enum.map(webinars, fn webinar -> %{webinar | url: nil} end)
  end

  defp show_only_preview_fields?(webinars, %{is_logged_in: true, plan_atom_name: plan})
       when plan != :pro do
    webinars
    |> Enum.map(fn
      %__MODULE__{is_pro: true} = webinar ->
        %{webinar | url: nil}

      %__MODULE__{is_pro: false} = webinar ->
        webinar
    end)
  end

  defp show_only_preview_fields?(webinars, %{is_logged_in: true, plan_atom_name: :pro}) do
    webinars
  end
end
