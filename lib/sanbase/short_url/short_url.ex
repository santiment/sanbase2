defmodule Sanbase.ShortUrl do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Repo

  @short_url_length 8

  schema "short_urls" do
    field(:short_url, :string)
    field(:full_url, :string)
    field(:data, :string)

    belongs_to(:user, Sanbase.Accounts.User)

    timestamps()
  end

  def changeset(%__MODULE__{} = url, attrs \\ %{}) do
    url
    |> cast(attrs, [:full_url, :short_url, :user_id, :data])
    |> validate_required([:full_url, :short_url])
    |> unique_constraint(:short_url)
  end

  def create(%{full_url: full_url} = args) when is_binary(full_url) do
    short_url =
      :crypto.strong_rand_bytes(@short_url_length)
      |> Base.url_encode64(padding: false)
      |> binary_part(0, @short_url_length)

    %__MODULE__{}
    |> changeset(Map.put(args, :short_url, short_url))
    |> Repo.insert()
  end

  def update(user_id, short_url, params) do
    case get(short_url) do
      %__MODULE__{user_id: ^user_id} = struct ->
        struct
        |> changeset(params)
        |> Repo.update()

      _ ->
        {:error,
         "The Short URL #{short_url} does not exist or belongs to another user and cannot be updated"}
    end
  end

  def get(short_url) when is_binary(short_url) do
    from(
      url in __MODULE__,
      where: url.short_url == ^short_url
    )
    |> Repo.one()
  end
end
