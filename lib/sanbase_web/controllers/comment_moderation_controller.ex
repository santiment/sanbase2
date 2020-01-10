defmodule SanbaseWeb.CommentModerationController do
  @resource "comments"
  use ExAdmin.Web, :resource_controller

  require Logger

  def anonymize_comment(conn, _defn, %{id: comment_id}) do
    resource = conn.assigns.resource

    %{user_id: user_id} = Sanbase.Insight.Comment.by_id(comment_id)

    case Sanbase.Insight.Comment.delete(comment_id, user_id) do
      {:ok, _} ->
        put_flash(conn, :notice, "Comment with id #{comment_id} anonymized")
        |> redirect(to: admin_resource_path(resource, :show))

      {:error, _} ->
        put_flash(conn, :error, "Failed to anonymize comment with id #{comment_id}")
        |> redirect(to: admin_resource_path(resource, :show))
    end
  end

  def delete_subcomment_tree(conn, _defn, %{id: comment_id}) do
    %{user_id: user_id} = Sanbase.Insight.Comment.by_id(comment_id)

    case Sanbase.Insight.Comment.delete_subcomment_tree(comment_id, user_id) do
      {:ok, _} ->
        put_flash(
          conn,
          :notice,
          "Deleted comment with #{comment_id} and its subcomments."
        )
        |> redirect(to: admin_resource_path(conn, :index))

      {:error, _} ->
        put_flash(
          conn,
          :error,
          "Failed to delete comment with id #{comment_id} and its subcomments"
        )
        |> redirect(to: admin_resource_path(conn, :index))
    end
  end
end
