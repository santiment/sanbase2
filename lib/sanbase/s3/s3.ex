defmodule Sanbase.S3 do
  @bucket "https://api-users-datasets.s3.eu-central-1.amazonaws.com"
  # https://api-users-datasets.s3.eu-central-1.amazonaws.com/new-users/
  def generate_presigned_url(resource, user_id) do
    config = Config.new(:s3, Application.get_all_env(:ex_aws))
    options = [expires_in: 7 * 86_400, virtual_host: false]
    ExAws.S3.presigned_url(config, :get, @bucket, "new-users", options)
  end
end
