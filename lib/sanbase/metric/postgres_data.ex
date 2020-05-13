defmodule Sanbase.Metric.MetricPostgresData do
  use Ecto.Schema

  import Ecto.Changeset

  schema "metrics" do
    field(:name, :string)

    many_to_many(:posts, Sanbase.Insight.Post,
      join_through: "posts_metrics",
      join_keys: [post_id: :id, metric_id: :id],
      on_replace: :delete,
      on_delete: :delete_all
    )

    timestamps()
  end

  def changeset(%__MODULE__{} = metric, attrs \\ %{}) do
    metric
    |> cast(attrs, [:name])
  end

  def put_metrics(%Ecto.Changeset{} = changeset, %{metrics: metrics}) when is_list(metrics) do
    metrics = metrics |> Enum.map(&%{name: &1})

    changeset
    |> put_assoc(:metrics, metrics)
  end

  def put_metrics(%Ecto.Changeset{} = changeset, _), do: changeset
end
