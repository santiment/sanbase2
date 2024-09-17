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

  def get(file_name) do
    case Application.get_env(:waffle, :storage) do
      Waffle.Storage.S3 ->
        :ok

      Waffle.Storage.Local ->
        :ok
    end
  end
end
