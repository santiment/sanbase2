defmodule SanbaseWeb.Admin.InvoiceDownloadController do
  use SanbaseWeb, :controller

  alias Sanbase.Billing.Invoices.{InvoiceArchive, S3Storage}

  def download(conn, %{"id" => id}) do
    case Sanbase.Repo.get(InvoiceArchive, id) do
      %{status: "completed", s3_key: s3_key} = archive when not is_nil(s3_key) ->
        if S3Storage.local_storage?() do
          local_path = S3Storage.local_file_path(s3_key)
          filename = "#{archive.year}_#{String.pad_leading(to_string(archive.month), 2, "0")}.zip"
          send_download(conn, {:file, local_path}, filename: filename)
        else
          case S3Storage.presigned_download_url(s3_key) do
            {:ok, url} -> redirect(conn, external: url)
            _ -> send_resp(conn, 404, "Could not generate download URL")
          end
        end

      _ ->
        send_resp(conn, 404, "Archive not found")
    end
  end
end
