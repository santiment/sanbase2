defmodule Sanbase.ApiCallLimit.Sync do
  @moduledoc """
  Force an update of the stored subscription plans for users in the api call limit table.

  When a subscription changes, the ApiCallLimit.update_user_plan/1 function must be
  explicitly invoked, otherwise the old api plan restrictions could still apply.
  To remedy this, invoke the update function once a day prophylactically.

  Processes users in batches to avoid loading all records into memory at once.
  """
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.ApiCallLimit

  @batch_size 500

  def run() do
    sync_in_batches(0)
  end

  defp sync_in_batches(last_id) do
    batch =
      from(acl in ApiCallLimit,
        where: not is_nil(acl.user_id) and acl.id > ^last_id,
        preload: [:user],
        order_by: [asc: acl.id],
        limit: @batch_size
      )
      |> Repo.all()

    case batch do
      [] ->
        :ok

      records ->
        Enum.each(records, fn acl -> ApiCallLimit.update_user_plan(acl.user) end)
        sync_in_batches(List.last(records).id)
    end
  end
end
