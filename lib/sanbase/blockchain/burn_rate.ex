defmodule Sanbase.Blockchain.BurnRate do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query
  import Sanbase.Timescaledb

  alias __MODULE__
  @primary_key false
  schema "eth_burn_rate" do
    field(:timestamp, :naive_datetime, primary_key: true)
    field(:contract_address, :string, primary_key: true)
    field(:burn_rate, :float)
  end

  def changeset(burn_rate, attrs \\ %{}) do
    burn_rate
    |> cast(attrs, [:timestamp, :contract_address, :burn_rate])
    |> validate_number(:burn_rate, greater_than_or_equal_to: 0.0)
    |> validate_length(:contract_address, min: 1)
  end

  def burn_rate(contract, from, to, interval) do
    from(
      br in __MODULE__,
      where: br.timestamp > ^from and br.timestamp < ^to and br.contract_address == ^contract,
      left_join:
        fragment(
          "select generate_series(current_date - interval '10 day', current_date, '1 day')::timestamp AS d"
        ),
      on: fragment("timestamp(?) = d", br.timestamp),
      select: {coalesce(sum(br.burn_rate), 0), time_bucket(^interval)},
      group_by: time_bucket(),
      order_by: time_bucket()
    )
    |> Sanbase.TimescaleRepo.all()
  end

  def fill_with_zero(query, from, to, interval) do
  end

  def period(%DateTime{} = from, %DateTime{} = to, interval) when is_integer(interval) do
    """
     SELECT timestamp
     FROM generate_series(timestamp '#{DateTime.to_naive(from)}', timestamp '#{
      DateTime.to_naive(to)
    }', interval '#{interval} minutes') timestamp
    """

    """
    select generate_series(current_date - interval '10 day', current_date, '1 day')::timestamp AS d
    """
    |> Sanbase.TimescaleRepo.query([])
  end

  #   SELECT time_bucket('2 weeks'::interval / 1080,  no_gaps) btime
  #   FROM  generate_series(now()-'2 weeks'::interval, now(), '2 weeks'::interval / 1080) no_gaps
  # end
end
