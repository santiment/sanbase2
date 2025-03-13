defmodule Sanbase.Admin.Permissions do
  defmodule Error do
    defexception [:message]
  end

  @view "Admin Panel Viewer"
  @owner "Admin Panel Owner"
  @edit "Admin Panel Editor"

  def can?(action, opts) do
    if @owner in Keyword.get(opts, :roles, []) do
      true
    else
      check_permission(action, opts)
    end
  end

  def raise_if_cannot(action, opts) do
    if not can?(action, opts) do
      raise __MODULE__.Error, message: "You don't have permission to #{action}"
    end
  end

  # Private functions

  def check_permission(:view, opts) do
    any_role?([@view], opts)
  end

  def check_permission(:create, opts) do
    any_role?([@edit], opts)
  end

  def check_permission(:edit, opts) do
    any_role?([@edit], opts)
  end

  # Helpers

  defp any_role?(any_of_these_roles, opts) do
    # If the user has any of thee roles listed, the user has permission
    user_roles = Keyword.get(opts, :roles, [])
    Enum.any?(any_of_these_roles, &(&1 in user_roles))
  end
end
