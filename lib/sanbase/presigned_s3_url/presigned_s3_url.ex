defmodule Sanbase.PresignedS3Url do
  @moduledoc ~s"""
  Give temporary access to precomputed datasets stored in AWS S3.

  The bucket holding the datasets is private, but users can generate
  presigned AWS S3 URLs that expire in 1-7 days and temporarily gain access
  to these datasets. The presigned URL includes a token, which grants that
  access.
  """
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias __MODULE__.S3
  @bucket "api-users-datasets"

  schema "presigned_s3_urls" do
    belongs_to(:user, Sanbase.Accounts.User)

    field(:bucket, :string)
    field(:object, :string)
    field(:presigned_url, :string)
    field(:expires_at, :utc_datetime)

    timestamps()
  end

  def changeset(%__MODULE__{} = url, attrs) do
    url
    |> cast(attrs, [:user_id, :bucket, :object, :presigned_url, :expires_at])
    |> validate_required([:user_id, :bucket, :object, :presigned_url, :expires_at])
    |> unique_constraint([:user_id, :bucket, :object])
  end

  @doc ~s"""

  """
  def get_presigned_s3_url(user_id, object) do
    query = from(url in __MODULE__, where: url.user_id == ^user_id and url.object == ^object)

    case Sanbase.Repo.one(query) do
      nil ->
        with {:ok, presigned_url} <- S3.generate_presigned_url(@bucket, object, 86400),
             {:ok, struct} <- store(user_id, @bucket, object, presigned_url, 86400) do
          {:ok, struct}
        end

      struct ->
        {:ok, struct}
    end
    |> replace_with_error_if_expired()
  end

  def store(user_id, bucket, object, presigned_url, expires_in) do
    expires_at = DateTime.utc_now() |> DateTime.add(expires_in, :second)

    %__MODULE__{}
    |> changeset(%{
      user_id: user_id,
      bucket: bucket,
      object: object,
      presigned_url: presigned_url,
      expires_at: expires_at
    })
    |> Sanbase.Repo.insert()
  end

  # Private functions

  defp replace_with_error_if_expired({:error, error}), do: {:error, error}

  defp replace_with_error_if_expired({:ok, struct}) do
    case DateTime.compare(DateTime.utc_now(), struct.expires_at) do
      :gt ->
        {:error, "The requested presigned S3 URL requested has expired at #{struct.expires_at}."}

      _ ->
        {:ok, struct}
    end
  end
end
