defmodule Sanbase.PresignedS3Url.S3 do
  require Sanbase.Utils.Config, as: Config

  def generate_presigned_url(bucket, object, expires_in) do
    config =
      ExAws.Config.new(:s3, Application.get_all_env(:ex_aws))
      |> Map.put(:access_key_id, Config.module_get(__MODULE__, :access_key_id))
      |> Map.put(:secret_access_key, Config.module_get(__MODULE__, :secret_access_key))

    options = [expires_in: expires_in, virtual_host: false]
    ExAws.S3.presigned_url(config, :get, bucket, object, options)
  end
end
