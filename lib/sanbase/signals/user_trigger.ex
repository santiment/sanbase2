defmodule Sanbase.Signals.UserTrigger do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias __MODULE__
  alias Sanbase.Auth.User
  alias Sanbase.Signals.Trigger
  alias Sanbase.Repo
  alias Sanbase.Signals.Trigger.{DailyActiveAddressesTrigger, PriceTrigger}

  @type trigger_struct :: %Trigger{}
  @type trigger_data_strct :: %DailyActiveAddressesTrigger{} | %PriceTrigger{}

  schema "user_triggers" do
    belongs_to(:user, User)
    embeds_one(:trigger, Trigger, on_replace: :update)

    timestamps()
  end

  def changeset(%UserTrigger{} = user_triggers, attrs \\ %{}) do
    user_triggers
    |> cast(attrs, [:user_id])
    |> cast_embed(:trigger, required: true, with: &Trigger.changeset/2)
    |> validate_required([:user_id])
  end

  @spec triggers_for(%User{}) :: list(trigger_struct)
  def triggers_for(%User{id: user_id}) do
    user_id
    |> user_triggers_for()
    |> Enum.map(fn ut -> trigger_in_struct(ut.trigger) end)
  end

  def get_trigger_by_id(%User{id: user_id} = _user, trigger_id) do
    user_triggers_for(user_id)
    |> find_user_trigger_by_trigger_id(trigger_id)
    |> Map.get(:trigger)
    |> trigger_in_struct()
  end

  @spec create_user_trigger(%User{}, map()) :: {:ok, list(trigger_struct)} | {:error, String.t()}
  def create_user_trigger(%User{id: user_id} = _user, %{trigger: trigger_data} = params) do
    if is_valid?(trigger_data) do
      %UserTrigger{}
      |> changeset(%{user_id: user_id, trigger: params})
      |> Repo.insert()
    else
      {:error, "Trigger structure is invalid"}
    end
  end

  def create_user_trigger(_, _), do: {:error, "Trigger structure is invalid"}

  def update_user_trigger(%User{id: user_id} = _user, %{id: id} = params) do
    trigger_data = Map.get(params, :trigger_data)

    if is_nil(trigger_data) or is_valid?(trigger_data) do
      user_id
      |> user_triggers_for()
      |> find_user_trigger_by_trigger_id(id)
      |> changeset(%{trigger: clean_params(params)})
      |> Repo.update()
    else
      {:error, "Trigger structure is invalid"}
    end
  end

  def update_user_trigger(_, _), do: {:error, "Trigger structure is invalid"}

  # Private functions

  defp user_triggers_for(user_id) do
    from(ut in UserTrigger, where: ut.user_id == ^user_id)
    |> Repo.all()
  end

  defp trigger_in_struct(trigger) do
    {:ok, trigger_data} = load_in_struct(trigger.trigger)
    %{trigger | trigger: trigger_data}
  end

  defp find_user_trigger_by_trigger_id(user_triggers, trigger_id) do
    user_triggers
    |> Enum.find(fn ut -> ut.trigger.id == trigger_id end)
  end

  defp is_valid?(trigger) do
    with {:ok, trigger_struct} <- load_in_struct(trigger),
         {:ok, _trigger_map} <- map_from_struct(trigger_struct) do
      true
    else
      _error ->
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
    _error in ArgumentError ->
      {:error, "Trigger structure is invalid"}
  end

  defp load_in_struct(_), do: :error

  defp struct_from_map(%{type: "daily_active_addresses"} = trigger),
    do: {:ok, struct!(DailyActiveAddressesTrigger, trigger)}

  defp struct_from_map(%{type: "price"} = trigger), do: {:ok, struct!(PriceTrigger, trigger)}
  defp struct_from_map(_), do: :error

  defp map_from_struct(%DailyActiveAddressesTrigger{} = trigger),
    do: {:ok, Map.from_struct(trigger)}

  defp map_from_struct(%PriceTrigger{} = trigger), do: {:ok, Map.from_struct(trigger)}
  defp map_from_struct(_), do: :error

  defp clean_params(params) do
    params
    |> Map.drop([:id])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end
end
