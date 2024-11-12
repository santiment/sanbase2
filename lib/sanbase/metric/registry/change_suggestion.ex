defmodule Sanbase.Metric.Registry.ChangeSuggestion do
  use Ecto.Schema

  alias Sanbase.Metric.Registry

  import Ecto.Query
  import Ecto.Changeset

  schema "metric_registry_change_suggestions" do
    belongs_to(:metric_registry, Registry)

    field(:notes, :string)
    field(:status, :string)
    field(:submitted_by, :string)

    field(:changes, :string)

    timestamps()
  end

  def changeset(%__MODULE__{} = struct, attrs) do
    struct
    |> cast(attrs, [
      :metric_registry_id,
      :notes,
      :changes,
      :status,
      :submitted_by
    ])
    |> validate_required([:metric_registry_id, :changes])
    |> validate_inclusion(:status, ["pending_approval", "approved", "rejected"])
  end

  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Sanbase.Repo.insert()
  end

  def list_all_submissions() do
    from(cs in __MODULE__, preload: [:metric_registry])
    |> Sanbase.Repo.all()
    |> Enum.map(fn struct -> %{struct | changes: decode_changes(struct.changes)} end)
  end

  def apply(%__MODULE__{} = suggestion) do
    {:ok, metric_registry} = Registry.by_id(suggestion.metric_registry_id)

    # The changes is a JSON map like {"1": "g3QAAAADdwNuZXdtAAAAAjFodwNvbGRtAAAAAjVtdwVmaWVsZHcMbWluX2ludGVydmFs"}
    # where the value is a base64 encoded binary produced by :erlang.term_to_binary
    # after decoding, the value is something like:
    # %{field: :min_interval, old: "5m", new: "1h"}
    changes =
      Map.new(
        suggestion.changes,
        fn {_k, encoded} ->
          %{key: key, old: _, new: new} =
            encoded
            |> Base.decode64!()
            |> :erlang.binary_to_term()

          %{key => new}
        end
      )

    metric_registry
    |> Registry.update(changes)
  end

  def create_change_suggestion(%Registry{} = registry, params, notes, submitted_by) do
    case Registry.changeset(registry, params) do
      %{valid?: false} = changeset ->
        {:error, changeset}

      %{valid?: true} = changeset ->
        old = changeset.data
        new = changeset |> Ecto.Changeset.apply_changes()

        changes = ExAudit.Diff.diff(old, new) |> encode_changes()

        %__MODULE__{}
        |> changeset(%{
          metric_registry_id: registry.id,
          notes: notes,
          submitted_by: submitted_by,
          changes: changes
        })
        |> Sanbase.Repo.insert()
    end
  end

  def encode_changes(changes) do
    changes
    |> :erlang.term_to_binary()
    |> Base.encode64()
  end

  def decode_changes(changes) do
    changes
    |> Base.decode64!()
    |> :erlang.binary_to_term()
  end
end
