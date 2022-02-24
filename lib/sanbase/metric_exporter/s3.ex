defmodule Sanbase.MetricExporter.S3 do
  use Waffle.Definition

  require Sanbase.Utils.Config, as: Config

  def bucket, do: Config.get(:bucket)

  def s3_object_headers(_version, {file, _scope}) do
    [content_type: MIME.from_path(file.file_name)]
  end

  def storage_dir(_first, {_, dir}) do
    dir
  end
end
