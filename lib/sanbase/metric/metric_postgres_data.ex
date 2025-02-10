defmodule Sanbase.Metric.MetricPostgresData do
  @moduledoc """
  Schema module that keeps the metric names in a postgres table.

  This table is referenced from different places like insights to expliclitly
  show what metrics are used.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo

  schema "metrics" do
    field(:name, :string)

    timestamps()
  end

  def changeset(%__MODULE__{} = metric, attrs \\ %{}) do
    cast(metric, attrs, [:name])
  end

  def put_metrics(%Ecto.Changeset{} = changeset, %{metrics: metrics}) when is_list(metrics) do
    metrics = by_names(metrics)

    put_assoc(changeset, :metrics, metrics)
  end

  def put_metrics(%Ecto.Changeset{} = changeset, _), do: changeset

  defp by_names(names) when is_list(names) do
    Repo.all(from(t in __MODULE__, where: t.name in ^names))
  end
end
