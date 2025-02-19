defmodule Sanbase.Metric.Registry.ChangeSuggestion do
  use Ecto.Schema

  alias Sanbase.Metric.Registry
  alias Sanbase.Utils.Config

  import Ecto.Query
  import Ecto.Changeset

  @statuses ["approved", "declined", "pending_approval"]
  schema "metric_registry_change_suggestions" do
    belongs_to(:metric_registry, Registry, foreign_key: :metric_registry_id)

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
    |> validate_required([:changes])
    |> validate_inclusion(:status, @statuses)
  end

  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Sanbase.Repo.insert()
  end

  def by_id(id) do
    case Sanbase.Repo.get(__MODULE__, id) do
      %__MODULE__{} = record -> {:ok, record}
      nil -> {:error, "Metric Registry Change Request with id #{id} not found"}
    end
  end

  def list_all_submissions() do
    from(cs in __MODULE__, preload: [:metric_registry])
    |> Sanbase.Repo.all()
  end

  def update_status(id, new_status) when is_integer(id) and new_status in @statuses do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_suggestion, fn _, _ -> by_id(id) end)
    |> Ecto.Multi.run(:maybe_apply_suggestions, fn _, %{get_suggestion: struct} ->
      if new_status == "approved" and struct.status == "pending_approval" do
        apply_suggestion(struct)
      else
        {:ok, :noop}
      end
    end)
    |> Ecto.Multi.run(:update_status, fn _, %{get_suggestion: struct} ->
      do_update_status(struct, new_status)
    end)
    |> Sanbase.Repo.transaction()
    |> case do
      {:ok,
       %{get_suggestion: struct, update_status: record, maybe_apply_suggestions: maybe_struct}} ->
        action_type =
          if struct.metric_registry_id, do: :update_metric_registry, else: :create_metric_registry

        handle_metric_regisry_action(action_type, maybe_struct)

        {:ok, record}

      {:error, _name, error, _changes_so_far} ->
        {:error, error}
    end
  end

  def undo(id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_suggestion, fn _, _ -> by_id(id) end)
    |> Ecto.Multi.run(:maybe_apply_suggestions, fn _, %{get_suggestion: struct} ->
      if struct.status == "approved" do
        undo_suggestion(struct)
      else
        {:ok, :noop}
      end
    end)
    |> Ecto.Multi.run(:update_status, fn _, %{get_suggestion: struct} ->
      do_update_status(struct, "pending_approval")
    end)
    |> Sanbase.Repo.transaction()
    |> case do
      {:ok, %{update_status: record, maybe_apply_suggestions: maybe_struct}} ->
        handle_metric_regisry_action(:update_metric_registry, maybe_struct)

        {:ok, record}

      {:error, _name, error, _changes_so_far} ->
        {:error, error}
    end
  end

  defp handle_metric_regisry_action(action_type, maybe_struct) do
    if match?(%Registry{}, maybe_struct) do
      Registry.EventEmitter.emit_event({:ok, maybe_struct}, action_type, %{})

      Node.list()
      |> Enum.each(fn node ->
        Node.spawn(node, fn ->
          # The caller is sanbase-admin pod. Emit the event to every of the sanbase-web pods
          # in the cluster.
          # Process the event only by the metric registry subscriber, otherwise the event
          # will be recorded multiple in kafka and trigger multiple notifications
          Registry.EventEmitter.emit_event({:ok, maybe_struct}, action_type, %{
            __only_process_by__: [Sanbase.EventBus.MetricRegistrySubscriber]
          })
        end)
      end)
    end
  end

  defp apply_suggestion(
         %__MODULE__{status: "pending_approval", metric_registry_id: nil} = suggestion
       ) do
    changes = decode_changes(suggestion.changes)
    params = changes_to_changeset_params(%Registry{}, changes)

    # Do not emit an event as this is called from within a transaction.
    Registry.create(params, emit_event: false)
  end

  defp apply_suggestion(%__MODULE__{status: "pending_approval"} = suggestion) do
    with {:ok, metric_registry} <- Registry.by_id(suggestion.metric_registry_id) do
      changes = decode_changes(suggestion.changes)
      apply_changes(suggestion, metric_registry, changes)
    end
  end

  defp undo_suggestion(%__MODULE__{status: "approved"} = suggestion) do
    with {:ok, metric_registry} <- Registry.by_id(suggestion.metric_registry_id) do
      changes = decode_changes(suggestion.changes) |> ExAudit.Diff.reverse()
      apply_changes(suggestion, metric_registry, changes)
    end
  end

  defp apply_changes(%__MODULE__{} = suggestion, %Registry{} = metric_registry, changes) do
    params = changes_to_changeset_params(metric_registry, changes)

    if Config.module_get(__MODULE__, :debug_applying_changes, false) do
      changeset =
        Registry.changeset(metric_registry, params)

      same_as_applying_patch? =
        Ecto.Changeset.apply_changes(changeset) == ExAudit.Patch.patch(metric_registry, changes)

      if !same_as_applying_patch? do
        raise("Applying patch failed for suggestion #{suggestion.id}")
      end
    end

    # Do not emit the event. After the transaction is commited and if the update is applied,
    # update_status/2 or undo/1 will emit the event. This is done so the event is emitted
    # only after the DB changes are commited and not from insite the transaction. If the event
    # is emitted from inside the transaction, the event handler can be invoked before the DB
    # changes are commited and this handler will have no effect.
    Sanbase.Metric.Registry.update(metric_registry, params, emit_event: false)
  end

  def create_change_suggestion(%Registry{} = registry, params, notes, submitted_by) do
    # After change suggestion is applied, put the metric in a unverified state and mark
    # is as not synced. Someone needs to manually verify the metric after it is tested.
    # When the data is synced between stage and prod, the sync status will be updated.

    # Convert all keys to strings so we don't get error if atom keys come from some caller
    params = Map.new(params, fn {k, v} -> {to_string(k), v} end)

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

  # Private

  defp do_update_status(%__MODULE__{} = record, new_status) do
    record
    |> changeset(%{status: new_status})
    |> Sanbase.Repo.update()
  end

  defp changes_to_changeset_params(metric_registry, changes) do
    Enum.reduce(changes, %{}, fn {key, change}, acc ->
      case change do
        {:changed, {:primitive_change, _old, new}} ->
          Map.put(acc, key, new)

        {:changed, [_ | _] = list} ->
          Map.put(acc, key, list_change(Map.fetch!(metric_registry, key), list))
      end
    end)
  end

  defp list_change(current_value_list, changes_list) when is_list(changes_list) do
    ExAudit.Patch.patch(current_value_list, changes_list)
    |> embeds_to_maps()

    # The old implementation. Remove at a later stage if no issues are discovered using ExAudit.Patch
    # changes_list
    # |> Enum.reduce(current_value_list, fn change_op, acc ->
    #   case change_op do
    #     {:added_to_list, pos, value} ->
    #       List.insert_at(acc, pos, value)
    #
    #     {:removed_from_list, pos, _value} ->
    #       # If we list like [1,2,3] and operations {:removed_from_list, 1, _}, {:removed_from_list, 2, _}
    #       # by the time we execute the second removal, the list will be with reduced size, so the
    #       # element won't be removed as there will be no element at position 2
    #       List.replace_at(acc, pos, :__deleted__)
    #
    #     {:changed_in_list, pos, map} ->
    #       [{embedded_schema_key, {:changed, {:primitive_change, _old, new}}}] = Map.to_list(map)
    #       List.update_at(acc, pos, &Map.put(&1, embedded_schema_key, new))
    #   end
    # end)
    # |> Enum.reject(&(&1 == :__deleted__))
  end

  defp embeds_to_maps(list) do
    # In changesets the embeds must be maps, not structs
    list
    |> Enum.map(fn
      struct when is_struct(struct) -> Map.from_struct(struct)
      map when is_map(map) -> map
    end)
  end
end
