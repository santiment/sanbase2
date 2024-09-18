defmodule Sanbase.Queries.ExternalData.Store do
  use Waffle.Definition

  @cache_max_age 0
  # 1Mb
  @max_file_size 1 * 1024 * 1024

  require Sanbase.Utils.Config, as: Config

  def bucket(), do: Config.module_get(__MODULE__, :bucket)

  def s3_object_headers(_version, {file, _scope}) do
    [
      content_type: MIME.from_path(file.file_name),
      cache_control: "max-age=#{@cache_max_age}"
    ]
  end

  def allowed_size?(file) do
    case File.stat(file.path) do
      {:ok, %{size: size}} when size <= @max_file_size ->
        true

      _ ->
        false
    end
  end

  def get_s3("s3://" <> _ = location) do
    req = Req.new() |> ReqS3.attach()

    # fetch from S3

    case Req.get(req, url: location) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "Returned status code #{status}"}
      {:error, error} -> {:error, error}
    end
  end

  def get_local(location) do
    File.read(location)
  end
end
