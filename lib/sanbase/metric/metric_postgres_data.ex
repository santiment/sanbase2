defmodule Sanbase.Metric.MetricPostgresData do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Insight.Post

  @posts_join_through_table "posts_metrics"
  schema "metrics" do
    field(:name, :string)

    many_to_many(:posts, Post,
      join_through: @posts_join_through_table,
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
    metrics = metrics |> by_names()

    changeset
    |> put_assoc(:metrics, metrics)
  end

  def put_metrics(%Ecto.Changeset{} = changeset, _), do: changeset

  defp by_names(names) when is_list(names) do
    from(t in __MODULE__, where: t.name in ^names)
    |> Repo.all()
  end
end
