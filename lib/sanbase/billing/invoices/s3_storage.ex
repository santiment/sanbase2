defmodule Sanbase.Billing.Invoices.S3Storage do
  @moduledoc """
  Handles S3 upload/download/delete for invoice archive ZIP files.
  In dev, falls back to local filesystem storage (same pattern as Waffle).
  In prod, uses ExAws.S3 directly.
  """

  @bucket_env_var "POSTS_IMAGE_BUCKET"
  @presigned_url_expiry 3600
  @local_storage_dir "/tmp/sanbase/filestore/invoice_archives"

  def upload_zip(zip_binary, year, month) do
    s3_key = s3_key(year, month)

    if local_storage?() do
      local_upload(s3_key, zip_binary)
    else
      ExAws.S3.put_object(bucket(), s3_key, zip_binary, content_type: "application/zip")
      |> ExAws.request()
      |> case do
        {:ok, _} -> {:ok, s3_key}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def delete_zip(s3_key) do
    if local_storage?() do
      local_delete(s3_key)
    else
      ExAws.S3.delete_object(bucket(), s3_key)
      |> ExAws.request()
      |> case do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def presigned_download_url(s3_key) do
    if local_storage?() do
      {:ok, "/tmp/sanbase/filestore/#{s3_key}"}
    else
      config = ExAws.Config.new(:s3, Application.get_all_env(:ex_aws))
      options = [expires_in: @presigned_url_expiry, virtual_host: false]
      ExAws.S3.presigned_url(config, :get, bucket(), s3_key, options)
    end
  end

  defp s3_key(year, month) do
    month_str = String.pad_leading(to_string(month), 2, "0")
    "invoice_archives/#{year}_#{month_str}.zip"
  end

  defp bucket do
    System.get_env(@bucket_env_var) || "sanbase-image-storage"
  end

  def local_storage? do
    Application.get_env(:waffle, :storage) == Waffle.Storage.Local
  end

  def local_file_path(s3_key) do
    Path.join(@local_storage_dir, Path.basename(s3_key))
  end

  defp local_upload(s3_key, data) do
    path = Path.join(@local_storage_dir, Path.basename(s3_key))

    with :ok <- File.mkdir_p(@local_storage_dir),
         binary = IO.iodata_to_binary(data),
         :ok <- File.write(path, binary) do
      {:ok, s3_key}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp local_delete(s3_key) do
    path = Path.join(@local_storage_dir, Path.basename(s3_key))

    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
