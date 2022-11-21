defmodule SanbaseWeb.Graphql.Resolvers.PresignedS3UrlResolver do
  import Sanbase.Utils.ErrorHandling, only: [changeset_errors_string: 1]
  import Absinthe.Resolution.Helpers

  alias Sanbase.PresignedS3Url

  require Logger

  def get_presigned_s3_url(_root, %{object: object} = args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    case PresignedS3Url.get_presigned_s3_url(current_user.id, object) do
      {:ok, %PresignedS3Url{presigned_url: url}} -> {:ok, url}
      {:error, error} -> {:error, error}
    end
  end
end
