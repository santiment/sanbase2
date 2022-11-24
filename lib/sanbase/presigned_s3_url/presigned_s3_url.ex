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
  @expires_in 86_400

  schema "presigned_s3_urls" do
    belongs_to(:user, Sanbase.Accounts.User)

    field(:bucket, :string)
    field(:object, :string)
    field(:presigned_url, :string)
    field(:expires_at, :utc_datetime)

    timestamps()
  end

  def bucket(), do: @bucket
  def expires_in(), do: @expires_in

  def changeset(%__MODULE__{} = url, attrs) do
    url
    |> cast(attrs, [:user_id, :bucket, :object, :presigned_url, :expires_at])
    |> validate_required([:user_id, :bucket, :object, :presigned_url, :expires_at])
    |> unique_constraint([:user_id, :bucket, :object])
  end

  @doc ~s"""
  Get a presigned S3 URL for sharing objects
  https://docs.aws.amazon.com/AmazonS3/latest/userguide/ShareObjectPreSignedURL.html

  The presigned URL gives a temporary access (expires in #{@expires_in} seconds)
  to an object in a private S3 bucket. A user can generate one URL per object.
  To track this, presigned S3 URLs are stored in a database table.
  """
  def get_presigned_s3_url(user_id, object) do
    query = from(url in __MODULE__, where: url.user_id == ^user_id and url.object == ^object)

    case Sanbase.Repo.one(query) do
      nil ->
        with {:ok, presigned_url} <- S3.generate_presigned_url(@bucket, object, @expires_in),
             {:ok, struct} <- store(user_id, @bucket, object, presigned_url, @expires_in) do
          {:ok, struct}
        end

      struct ->
        {:ok, struct}
    end
    |> replace_with_error_if_expired()
  end

  # Private functions

  defp store(user_id, bucket, object, presigned_url, expires_in) do
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

  defp replace_with_error_if_expired({:error, error}), do: {:error, error}

  defp replace_with_error_if_expired({:ok, struct}) do
    case DateTime.compare(DateTime.utc_now(), struct.expires_at) do
      :gt ->
        {:error,
         "A presigned S3 URL has been generated and has already expired at #{struct.expires_at}."}

      _ ->
        {:ok, struct}
    end
  end
end
