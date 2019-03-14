defmodule SanbaseWeb.ExAdmin.UserTriggerController do
  @resource "models"
  use ExAdmin.Web, :resource_controller

  def mark_featured(conn, defn, params) do
    resource = conn.assigns.resource

    IO.inspect("AKJHASKDHASLDJALSJKDALSKJLASDJ")

    changeset =
      apply(defn.resource_model, defn.update_changeset, [resource, params[defn.resource_name]])
  end
end
