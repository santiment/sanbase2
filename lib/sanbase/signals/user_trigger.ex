defmodule Sanbase.Signals.UserTrigger do
  @moduledoc ~s"""
  Module that implements the connectionb between a user and a trigger.
  It provides functionsn for creating and updating such user triggerrs. Also
  this is the struct that is used in the `Sanbase.Signals.Evaluator` because it
  needs to know the user to whom the signal needs to be sent.
  """
  @derive [Sanbase.Signal, Jason.Encoder]

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query
  import Sanbase.Signals.TriggerQuery
  import Sanbase.Signals.StructMapTransformation

  alias __MODULE__
  alias Sanbase.Auth.User
  alias Sanbase.Signals.Trigger
  alias Sanbase.Repo
  alias Sanbase.Tag

  require Logger

  schema "user_triggers" do
    belongs_to(:user, User)
    embeds_one(:trigger, Trigger, on_replace: :update)

    many_to_many(
      :tags,
      Tag,
      join_through: "user_triggers_tags",
      on_replace: :delete,
      on_delete: :delete_all
    )

    timestamps()
  end

  @doc false
  @spec create_changeset(%UserTrigger{}, map()) :: Ecto.Changeset.t()
  def create_changeset(%UserTrigger{} = user_triggers, attrs \\ %{}) do
    user_triggers
    |> cast(attrs, [:user_id])
    |> Tag.put_tags(Map.get(attrs, :trigger, %{}))
    |> cast_embed(:trigger, required: true, with: &Trigger.create_changeset/2)
    |> validate_required([:user_id, :trigger])
  end

  @doc false
  @spec update_changeset(%UserTrigger{}, map()) :: Ecto.Changeset.t()
  def update_changeset(%UserTrigger{} = user_triggers, attrs \\ %{}) do
    user_triggers
    |> cast(attrs, [:user_id])
    |> Tag.put_tags(Map.get(attrs, :trigger, %{}))
    |> cast_embed(:trigger, required: true, with: &Trigger.update_changeset/2)
    |> validate_required([:user_id, :trigger])
  end

  @doc ~s"""
  Get all triggers for the user with id `user_id`
  The result is transformed so all trigger settings are loaded in their
  corresponding struct
  """
  @spec triggers_for(%User{}) :: list(Trigger.t())
  def triggers_for(%User{id: user_id}) do
    user_id
    |> user_triggers_for()
  end

  @doc ~s"""
  Get all public triggers for the user with id `user_id`
  The result is transformed so all trigger settings are loaded in their
  corresponding struct
  """
  @spec public_triggers_for(non_neg_integer()) :: list(Trigger.t())
  def public_triggers_for(user_id) do
    user_id
    |> public_user_triggers_for()
  end

  @doc ~s"""
  Get all public triggers from the database
  """
  @spec all_public_triggers() :: list(%__MODULE__{})
  def all_public_triggers() do
    from(ut in UserTrigger, where: trigger_is_public())
    |> Repo.all()
    |> Enum.map(&trigger_in_struct/1)
  end

  @doc ~s"""
  Get the trigger that has UUID `trigger_id` if and only if it is owned by the
  user with id `user_id`
  """
  def get_trigger_by_id(%User{id: user_id} = _user, trigger_id) do
    result =
      from(
        ut in UserTrigger,
        where: ut.user_id == ^user_id and trigger_by_id(trigger_id),
        preload: [:tags]
      )
      |> Repo.one()
      |> case do
        %UserTrigger{} = ut ->
          ut |> trigger_in_struct()

        nil ->
          nil
      end

    {:ok, result}
  end

  @doc ~s"""
  Get all triggers of a given type. Returns both public and private as it is used
  to run the signals evaluator and not in the public API.
  """
  @spec get_triggers_by_type(String.t()) :: list(%__MODULE__{})
  def get_triggers_by_type(type) do
    from(
      ut in UserTrigger,
      where: trigger_type_is(type),
      preload: [{:user, :user_settings}]
    )
    |> Repo.all()
    |> Enum.map(&trigger_in_struct/1)
  end

  @doc ~s"""
  Create a new user trigger that is used to fire signals.
  To create a new trigger `settings` and `title` parameters must be present
  """
  @spec create_user_trigger(%User{}, map()) ::
          {:ok, %__MODULE__{}} | {:error, String.t()} | {:error, %Ecto.Changeset{}}
  def create_user_trigger(%User{id: user_id} = _user, %{settings: settings} = params) do
    if not is_nil(settings) and is_valid?(settings) do
      %UserTrigger{}
      |> create_changeset(%{user_id: user_id, trigger: params})
      |> Repo.insert()
    else
      {:error, "Trigger structure is invalid"}
    end
  end

  def create_user_trigger(_, _), do: {:error, "Trigger structure is invalid"}

  @doc ~s"""
  Update an existing user trigger with a given UUID `trigger_id`.
  There are not required parameters.
  """
  @spec update_user_trigger(%User{}, map()) ::
          {:ok, %__MODULE__{}} | {:error, String.t()} | {:error, Ecto.Changeset.t()}
  def update_user_trigger(%User{} = user, %{id: trigger_id} = params) do
    settings = Map.get(params, :settings)

    if is_nil(settings) or is_valid?(settings) do
      {:ok, struct} = get_trigger_by_id(user, trigger_id)

      struct
      |> update_changeset(%{trigger: clean_params(params)})
      |> Repo.update()
    else
      {:error, "Trigger structure is invalid"}
    end
  end

  def update_user_trigger(_, _), do: {:error, "Trigger structure is invalid"}

  @doc ~s"""
  Remove an existing user trigger with a given UUID `trigger_id`.
  """
  @spec remove_user_trigger(%User{}, String.t()) ::
          {:ok, %__MODULE__{}} | {:error, String.t()} | {:error, Ecto.Changeset.t()}
  def remove_user_trigger(%User{} = user, trigger_id) do
    case get_trigger_by_id(user, trigger_id) do
      {:ok, struct} ->
        Repo.delete(struct)

      _ ->
        {:error, "Can't remove trigger wit id #{trigger_id}"}
    end
  @spec historical_trigger_points(%Trigger{}) :: list(any)
  def historical_trigger_points(%Trigger{} = trigger) do
    Trigger.historical_trigger_points(trigger)
  end

  @spec historical_trigger_points(map()) :: list(any)
  def historical_trigger_points(%{settings: settings} = params) do
    {:ok, settings_struct} =
      settings
      |> load_in_struct()

    trigger = struct!(Trigger, params)

    Trigger.historical_trigger_points(%{trigger | settings: settings_struct})
  end

  # Private functions

  defp user_triggers_for(user_id) do
    from(ut in UserTrigger, where: ut.user_id == ^user_id, preload: [:tags])
    |> Repo.all()
    |> Enum.map(&trigger_in_struct/1)
  end

  defp public_user_triggers_for(user_id) do
    from(ut in UserTrigger,
      where: ut.user_id == ^user_id and trigger_is_public(),
      preload: [:tags]
    )
    |> Repo.all()
    |> Enum.map(&trigger_in_struct/1)
  end

  defp is_valid?(trigger) do
    with {:ok, trigger_struct} <- load_in_struct(trigger),
         true <- Vex.valid?(trigger_struct),
         {:ok, _trigger_map} <- map_from_struct(trigger_struct) do
      true
    else
      false ->
        {:ok, trigger_struct} = load_in_struct(trigger)
        Logger.warn("UserTrigger struct is not valid: #{inspect(Vex.errors(trigger_struct))}")
        false

      _ ->
        false
    end
  end

  defp clean_params(params) do
    params
    |> Map.drop([:id])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end
end
