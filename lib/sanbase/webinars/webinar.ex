defmodule Sanbase.Webinar do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

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
    cast(webinar, attrs, [:title, :description, :url, :image_url, :start_time, :end_time, :is_pro])
  end

  @doc false
  def changeset(webinar, attrs) do
    webinar
    |> cast(attrs, [:title, :description, :url, :image_url, :start_time, :end_time, :is_pro])
    |> validate_required([
      :title,
      :description,
      :url,
      :image_url,
      :start_time,
      :end_time,
      :is_pro
    ])
  end

  def by_id(id) do
    Repo.get(__MODULE__, id)
  end

  def list do
    Repo.all(from(w in __MODULE__, order_by: [desc: w.inserted_at]))
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
    Repo.delete(webinar)
  end

  def get_all(opts) do
    show_only_preview_fields?(list(), opts)
  end

  defp show_only_preview_fields?(webinars, %{plan_name: plan}) when plan in ["PRO", "PRO_PLUS", "MAX"] do
    webinars
  end

  defp show_only_preview_fields?(webinars, _) do
    Enum.map(webinars, fn
      %__MODULE__{is_pro: true} = webinar ->
        %{webinar | url: nil}

      %__MODULE__{is_pro: false} = webinar ->
        webinar
    end)
  end
end
