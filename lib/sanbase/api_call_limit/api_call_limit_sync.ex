defmodule Sanbase.ApiCallLimit.Sync do
  @moduledoc """
  Force an update of the stored subscription plans for users in the api call limit table.

  When a subscription changes, the ApiCallLimit.update_user_plan/1 function must be
  explicitly invoked, otherwise the old api plan restrictions could still apply.
  To remedy this, invoke the update function once a day prophylactically.
  """
  import Ecto.Query

  alias Sanbase.ApiCallLimit
  alias Sanbase.Repo

  def run do
    from(acl in ApiCallLimit, where: not is_nil(acl.user_id), preload: [:user])
    |> Repo.all()
    |> Enum.map(& &1.user)
    |> Enum.each(&ApiCallLimit.update_user_plan/1)
  end
end
