defmodule Sanbase.Signals.UserTriggers do
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__
  alias Sanbase.Auth.User
  alias Sanbase.Signals.Trigger
  alias Sanbase.Repo
  alias Sanbase.Signals.Trigger.{DaaTrigger, PriceTrigger}

  schema "user_triggers" do
    belongs_to(:user, User)
    embeds_many(:triggers, Trigger)

    timestamps()
  end

  def changeset(%UserTriggers{} = user_triggers, attrs \\ %{}) do
    user_triggers
    |> cast(attrs, [:user_id])
    |> cast_embed(:triggers, required: true, with: &Trigger.changeset/2)
    |> validate_required([:user_id])
    |> unique_constraint(:user_id)
  end

  def triggers_for(%User{id: user_id}) do
    Repo.get_by(UserTriggers, user_id: user_id)
    |> case do
      nil ->
        []

      %UserTriggers{} = ut ->
        triggers_in_struct(ut)
    end
  end

  def get_trigger(%User{id: user_id} = user, trigger_id) do
    triggers_for(user)
    |> find_trigger_by_id(trigger_id)
  end

  def create_trigger(%User{id: user_id} = user, trigger) do
    if is_valid?(trigger) do
      triggers = triggers_map_for(user)

      triggers_update(user_id, triggers ++ [%{trigger: trigger}])
      |> case do
        {:ok, ut} ->
          {:ok, triggers_in_struct(ut)}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, "Trigger structure is invalid"}
    end
  end

  def create_trigger(_, _), do: {:error, "Trigger structure is invalid"}

  def update_trigger(%User{id: user_id} = user, %{id: id, trigger: trigger}) do
    if is_valid?(trigger) do
      triggers =
        user
        |> triggers_map_for()
        |> find_and_update_trigger(id, trigger)

      triggers_update(user_id, triggers)
      |> case do
        {:ok, ut} ->
          {:ok, triggers_in_struct(ut)}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, "Trigger structure is invalid"}
    end
  end

  def update_trigger(_, _), do: {:error, "Trigger structure is invalid"}

  # Private functions

  defp triggers_in_struct(user_triggers) do
    user_triggers.triggers
    |> Enum.map(fn t ->
      {:ok, trigger} = load_in_struct(t.trigger)
      Map.put(t, :trigger, trigger)
    end)
  end

  defp triggers_map_for(%User{id: user_id}) do
    Repo.get_by(UserTriggers, user_id: user_id)
    |> case do
      nil ->
        []

      %UserTriggers{} = ut ->
        ut.triggers
        |> Enum.map(fn trigger ->
          trigger
          |> Map.from_struct()
        end)
    end
  end

  defp find_trigger_by_id(triggers, trigger_id) do
    triggers
    |> Enum.find(fn t -> t.id == trigger_id end)
  end

  defp find_and_update_trigger(triggers, new_trigger_id, new_trigger) do
    triggers
    |> Enum.map(fn existing_trigger ->
      if existing_trigger.id == new_trigger_id do
        Map.put(existing_trigger, :trigger, new_trigger)
      else
        existing_trigger
      end
    end)
  end

  defp triggers_update(user_id, triggers) do
    Repo.get_by(UserTriggers, user_id: user_id)
    |> case do
      nil ->
        changeset(%UserTriggers{}, %{user_id: user_id, triggers: triggers})

      %UserTriggers{} = ut ->
        changeset(ut, %{triggers: triggers})
    end
    |> Repo.insert_or_update()
  end

  defp is_valid?(trigger) do
    with {:ok, trigger_struct} <- load_in_struct(trigger),
         {:ok, trigger_map} <- map_from_struct(trigger_struct) do
      true
    else
      error ->
        false
    end
  end

  defp load_in_struct(trigger) when is_map(trigger) do
    trigger =
      for {key, val} <- trigger, into: %{} do
        if is_atom(key) do
          {key, val}
        else
          {String.to_existing_atom(key), val}
        end
      end

    struct_from_map(trigger)
  rescue
    e in ArgumentError ->
      {:error, "Trigger structure is invalid"}
  end

  defp load_in_struct(_), do: :error

  defp struct_from_map(%{type: "daa"} = trigger), do: {:ok, struct!(DaaTrigger, trigger)}
  defp struct_from_map(%{type: "price"} = trigger), do: {:ok, struct!(PriceTrigger, trigger)}
  defp struct_from_map(_), do: :error

  defp map_from_struct(%DaaTrigger{} = trigger), do: {:ok, Map.from_struct(trigger)}
  defp map_from_struct(%PriceTrigger{} = trigger), do: {:ok, Map.from_struct(trigger)}
  defp map_from_struct(_), do: :error
end
