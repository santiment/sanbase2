defmodule Sanbase.PresignedS3Url.S3 do
  @moduledoc false
  require Sanbase.Utils.Config, as: Config

  @doc ~s"""
  Generate a presigned S3 URL to share a S3 object in the given bucket.
  """
  @spec generate_presigned_url(String.t(), String.t(), non_neg_integer()) ::
          {:ok, binary()} | {:error, binary()}
  def generate_presigned_url(bucket, object, expires_in) do
    config =
      :s3
      |> ExAws.Config.new(Application.get_all_env(:ex_aws))
      |> Map.put(:access_key_id, Config.module_get(__MODULE__, :access_key_id))
      |> Map.put(:secret_access_key, Config.module_get(__MODULE__, :secret_access_key))

    options = [expires_in: expires_in, virtual_host: false]
    ExAws.S3.presigned_url(config, :get, bucket, object, options)
  end

  def utc_now do
    # Have a separate function so it can be mocked in the test without
    # explicitly mocking DateTime.utc_now/0, which will conflict with other
    # parts of the code like authentication
    DateTime.utc_now()
  end
end
