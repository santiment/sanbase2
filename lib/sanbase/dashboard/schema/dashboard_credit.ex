defmodule Sanbase.Dashboard.Credit do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Dashboard
  alias Sanbase.Accounts.User

  schema "dashboard_credits" do
    belongs_to(:dashboard, Dashboard)
    belongs_to(:user, User)

    field(:panel_id, :string)
    field(:query_id, :string)
    field(:query_data, :map)
    field(:credits_cost, :integer)

    timestamps()
  end

  def credits_spent(user_id, from, to) do
    credits_cost =
      from(c in __MODULE__,
        where: c.user_id == ^user_id and c.inserted_at >= ^from and c.inserted_at <= ^to,
        select: sum(c.credits_cost)
      )
      |> Sanbase.Repo.one()

    {:ok, credits_cost || 0}
  end

  @fields [:dashboard_id, :panel_id, :user_id, :panel_id, :query_id, :query_data, :credits_cost]
  def store_computation(user_id, args) do
    # TODO

    args = Map.put(args, :credits_cost, compute_credits_cost(args.query_id))

    %__MODULE__{}
    |> cast(args, @fields)
    |> validate_required(@fields)
  end

  defp compute_credits_cost(query_id) do
    # TODO
    {:ok, query_data} = get_query_data(query_id, DateTime.utc_now())
  end

  defp get_query_data(query_id, executed_at) do
    query = """
    SELECT
      ProfileEvents['ReadCompressedBytes'] / pow(2,30) AS read_compressed_gb,
      memory_usage / pow(2, 30) AS memory_usage_gb,
      read_rows,
      read_bytes / pow(2, 30) AS read_gb,
      result_rows,
      result_bytes / pow(2, 30) AS result_gb
    FROM system.query_log
    PREWHERE
      query_id = ?1 AND
      event_time >= ?2 - INTERVAL 15 MINUTE AND
      event_time <= ?1 + INTERVAL 15 MINUTE
    """

    args = [query_id, DateTime.to_unix(executed_at)]

    Sanbase.ClickhouseRepo.query_transform(
      query,
      args,
      fn [
           read_compressed_db,
           memory_usage_gb,
           read_rows,
           read_gb,
           result_rows,
           result_gb
         ] ->
        %{
          read_compressed_db: read_compressed_db,
          memory_usage_gb: memory_usage_gb,
          read_rows: read_rows,
          read_gb: read_gb,
          result_rows: result_rows,
          result_gb: result_gb
        }
      end
    )
    |> Sanbase.Utils.Transform.maybe_unwrap_ok_value()
  end
end
