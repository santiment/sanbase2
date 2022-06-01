defmodule Sanbase.Dashboard.Credit do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Dashboard
  alias Sanbase.Accounts.User

  @type user_id :: non_neg_integer()

  schema "dashboard_credits" do
    belongs_to(:dashboard, Dashboard.Schema)
    belongs_to(:user, User)

    field(:panel_id, :string)
    field(:query_id, :string)
    field(:query_data, :map)
    field(:credits_cost, :integer)

    timestamps()
  end

  @spec credits_spent(user_id, DateTime.t(), DateTime.t()) :: {:ok, non_neg_integer()}
  def credits_spent(user_id, from, to) do
    credits_cost =
      from(c in __MODULE__,
        where: c.user_id == ^user_id and c.inserted_at >= ^from and c.inserted_at <= ^to,
        select: sum(c.credits_cost)
      )
      |> Sanbase.Repo.one()

    {:ok, credits_cost || 0}
  end

  @fields [:dashboard_id, :panel_id, :user_id, :panel_id, :s, :query_data, :credits_cost]
  def store_computation(user_id, args) do
    %{credits_cost: credits_cost, query_data: query_data} = compute_credits_cost(args)

    credits_cost =
      Enum.max([Float.round(credits_cost), 1])
      |> Kernel.trunc()

    args =
      args
      |> Map.take(@fields)
      |> Map.merge(%{credits_cost: credits_cost, user_id: user_id, query_data: query_data})

    %__MODULE__{}
    |> cast(args, @fields)
    |> validate_required(@fields)
    |> Sanbase.Repo.insert()
  end

  # Private functions

  defp compute_credits_cost(args) do
    %{query_id: query_id, query_start: query_start} = args
    {:ok, query_data} = get_query_data(query_id, query_start)

    # The credits cost is computed as the dot product of the vectors
    # representing the statistics' values and the weights, i.e
    # value(read_gb)*weight(read_gb) + value(result_gb)*weight(result_gb) + ...
    # The values for the weights are manually picked. They are going to be tuned
    # as times go by.
    weights = %{
      read_compressed_gb: 0.2,
      cpu_time_microseconds: 0.0000007,
      query_duration_ms: 0.005,
      memory_usage_gb: 20,
      read_rows: 0.00000001,
      read_gb: 0.05,
      result_rows: 0.001,
      result_gb: 2000
    }

    credits_cost =
      Map.merge(query_data, weights, fn _k, value, weight -> value * weight end)
      |> Map.values()
      |> Enum.sum()

    %{query_data: query_data, credits_cost: credits_cost}
  end

  defp get_query_data(query_id, event_time_start) do
    query = """
    SELECT
      ProfileEvents['ReadCompressedBytes'] / pow(2,30) AS read_compressed_gb,
      ProfileEvents['OSCPUVirtualTimeMicroseconds'] AS cpu_time_microseconds,
      query_duration_ms,
      memory_usage / pow(2, 30) AS memory_usage_gb,
      read_rows,
      read_bytes / pow(2, 30) AS read_gb,
      result_rows,
      result_bytes / pow(2, 30) AS result_gb
    FROM system.query_log_distributed
    PREWHERE
      query_id = ?1 AND
      type = 'QueryFinish' AND
      event_time >= toDateTime(?2) - INTERVAL 1 MINUTE AND
      event_time <= toDateTime(?2) + INTERVAL 1 MINUTE
    """

    args = [query_id, DateTime.to_unix(event_time_start)]

    Sanbase.ClickhouseRepo.query_transform(
      query,
      args,
      fn [
           read_compressed_gb,
           cpu_time_microseconds,
           query_duration_ms,
           memory_usage_gb,
           read_rows,
           read_gb,
           result_rows,
           result_gb
         ] ->
        %{
          read_compressed_gb: Float.round(read_compressed_gb, 6),
          cpu_time_microseconds: cpu_time_microseconds,
          query_duration_ms: query_duration_ms,
          memory_usage_gb: Float.round(memory_usage_gb, 6),
          read_rows: read_rows,
          read_gb: Float.round(read_gb, 6),
          result_rows: result_rows,
          result_gb: Float.round(result_gb, 6)
        }
      end
    )
    |> Sanbase.Utils.Transform.maybe_unwrap_ok_value()
  end
end
