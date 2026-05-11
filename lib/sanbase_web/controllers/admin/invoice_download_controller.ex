defmodule SanbaseWeb.Admin.InvoiceDownloadController do
  use SanbaseWeb, :controller

  alias Sanbase.Billing.Invoices.{InvoiceArchive, S3Storage}

  # Finance data: restrict download to Admin Panel Owners. Viewer/Editor
  # admins have no business-need for raw invoice archives.
  @allowed_role_ids [
    Sanbase.Accounts.Role.admin_panel_editor_role_id(),
    Sanbase.Accounts.Role.admin_panel_owner_role_id()
  ]

  def download(conn, %{"id" => id}) do
    if authorized?(conn) do
      serve_download(conn, id)
    else
      conn
      |> put_status(403)
      |> text("Forbidden: invoice download requires Admin Panel Owner role")
    end
  end

  defp authorized?(conn) do
    case conn.assigns[:current_user] do
      %Sanbase.Accounts.User{} = user ->
        Enum.any?(user.roles, fn ur -> ur.role.id in @allowed_role_ids end)

      _ ->
        false
    end
  end

  defp serve_download(conn, id) do
    case Sanbase.Repo.get(InvoiceArchive, id) do
      %{status: "completed", s3_key: s3_key} = archive when not is_nil(s3_key) ->
        if S3Storage.local_storage?() do
          local_path = S3Storage.local_file_path(s3_key)

          if File.exists?(local_path) do
            filename =
              "#{archive.year}_#{String.pad_leading(to_string(archive.month), 2, "0")}.zip"

            send_download(conn, {:file, local_path}, filename: filename)
          else
            send_resp(conn, 404, "Archive file not found on disk")
          end
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
