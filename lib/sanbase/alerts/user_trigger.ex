defmodule Sanbase.Alert.UserTrigger do
  @moduledoc ~s"""
  Module that implements the connectionb between a user and a trigger.
  It provides functionsn for creating and updating such user triggerrs. Also
  this is the struct that is used in the `Sanbase.Alert.Evaluator` because it
  needs to know the user to whom the alert needs to be sent.
  """
  use Ecto.Schema

  @behaviour Sanbase.Entity.Behaviour

  import Ecto.Changeset
  import Ecto.Query
  import Sanbase.Alert.EventEmitter, only: [emit_event: 3]
  import Sanbase.Utils.Transform, only: [to_bang: 1]
  import Sanbase.Alert.TriggerQuery
  import Sanbase.Alert.StructMapTransformation

  alias __MODULE__
  alias Sanbase.Accounts.User
  alias Sanbase.Alert.{Trigger, HistoricalActivity}
  alias Sanbase.Repo
  alias Sanbase.Tag
  alias Sanbase.Timeline.TimelineEvent

  require Logger

  @derive [Sanbase.Alert, Jason.Encoder]

  @type trigger_id :: non_neg_integer()

  schema "user_triggers" do
    field(:is_deleted, :boolean, default: false)
    field(:is_hidden, :boolean, default: false)

    belongs_to(:user, User)
    embeds_one(:trigger, Trigger, on_replace: :update)

    many_to_many(
      :tags,
      Tag,
      join_through: "user_triggers_tags",
      on_replace: :delete,
      on_delete: :delete_all
    )

    has_one(:featured_item, Sanbase.FeaturedItem, on_delete: :delete_all)
    has_many(:alerts_historical_activity, HistoricalActivity, on_delete: :delete_all)
    has_many(:timeline_events, TimelineEvent, on_delete: :delete_all)

    # Virtual fields
    field(:views, :integer, virtual: true, default: 0)
    field(:is_featured, :boolean, virtual: true)
    field(:is_public, :boolean, virtual: true)

    timestamps()
  end

  def changeset(ut, attrs \\ %{}) do
    ut |> cast(attrs, [])
  end

  def public?(%__MODULE__{trigger: %{is_public: is_public}}), do: is_public

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
    |> cast(attrs, [:user_id, :is_deleted, :is_hidden])
    |> Tag.put_tags(Map.get(attrs, :trigger, %{}))
    |> cast_embed(:trigger, required: true, with: &Trigger.update_changeset/2)
    |> validate_required([:user_id, :trigger])
  end

  def update_is_active(user_trigger_id, user_id, is_active) do
    update_user_trigger(user_id, %{
      id: user_trigger_id,
      is_active: is_active
    })
  end

  @impl Sanbase.Entity.Behaviour
  def by_id!(id, opts) when is_integer(id), do: by_id(id, opts) |> to_bang()

  @impl Sanbase.Entity.Behaviour
  def by_id(id, _opts) when is_integer(id) do
    query = from(ut in base_query(), where: ut.id == ^id)

    case Repo.one(query) do
      nil -> {:error, "UserTrigger with id: #{id} does not exist"}
      ut -> {:ok, ut |> trigger_in_struct()}
    end
  end

  @impl Sanbase.Entity.Behaviour
  def by_ids!(ids, opts) when is_list(ids), do: by_ids(ids, opts) |> to_bang()

  @impl Sanbase.Entity.Behaviour
  def by_ids(ids, opts) when is_list(ids) do
    preload = Keyword.get(opts, :preload, [:featured_item, :tags])

    result =
      from(ul in base_query(),
        where: ul.id in ^ids,
        preload: ^preload,
        order_by: fragment("array_position(?, ?::int)", ^ids, ul.id)
      )
      |> Repo.all()
      |> Enum.map(&trigger_in_struct/1)

    {:ok, result}
  end

  # The base of all the entity queries
  defp base_entity_ids_query(opts) do
    base_query()
    |> maybe_apply_projects_filter(opts)
    |> Sanbase.Entity.Query.maybe_filter_is_hidden(opts)
    |> Sanbase.Entity.Query.maybe_filter_is_featured_query(opts, :user_trigger_id)
    |> Sanbase.Entity.Query.maybe_filter_by_users(opts)
    |> Sanbase.Entity.Query.maybe_filter_by_cursor(:inserted_at, opts)
    |> select([ul], ul.id)
  end

  @impl Sanbase.Entity.Behaviour
  def public_and_user_entity_ids_query(user_id, opts) do
    base_entity_ids_query(opts)
    |> where([ul], public_trigger?() or ul.user_id == ^user_id)
  end

  @impl Sanbase.Entity.Behaviour
  def public_entity_ids_query(opts) do
    base_entity_ids_query(opts)
    |> where([ul], public_trigger?())
  end

  @impl Sanbase.Entity.Behaviour
  def user_entity_ids_query(user_id, opts) do
    # Disable the filter by users
    opts = Keyword.put(opts, :user_ids, nil)

    base_entity_ids_query(opts)
    |> where([ul], ul.user_id == ^user_id)
  end

  @doc ~s"""
  Get all triggers for the user with id `user_id`
  The result is transformed so all trigger settings are loaded in their
  corresponding struct
  """
  @spec triggers_for(non_neg_integer()) :: list(%UserTrigger{})
  def triggers_for(user_id) when is_integer(user_id) and user_id > 0 do
    user_id
    |> user_triggers_for()
  end

  @spec triggers_count_for(non_neg_integer()) :: integer()
  def triggers_count_for(user_id) when is_integer(user_id) and user_id > 0 do
    base_query()
    |> where([ut], ut.user_id == ^user_id)
    |> select([_], fragment("count(*)"))
    |> Repo.one()
  end

  @doc ~s"""
  Get all public triggers for the user with id `user_id`
  The result is transformed so all trigger settings are loaded in their
  corresponding struct
  """
  @spec public_triggers_for(non_neg_integer()) :: list(%UserTrigger{})
  def public_triggers_for(user_id), do: user_id |> public_user_triggers_for()

  @doc ~s"""
  Get all public triggers from the database
  """
  @spec all_public_triggers() :: list(%UserTrigger{})
  def all_public_triggers() do
    from(ut in base_query(), where: public_trigger?(), preload: [:tags])
    |> Repo.all()
    |> Enum.map(&trigger_in_struct/1)
  end

  @doc ~s"""
  Get the trigger that has an id `trigger_id` if and only if it is owned by the
  user with id `user_id`
  """
  @spec by_user_and_id(non_neg_integer() | nil, trigger_id) :: {:ok, %UserTrigger{} | nil}
  def by_user_and_id(user_id, trigger_id)
      when is_nil(user_id) or (is_integer(user_id) and user_id > 0) do
    user_trigger =
      by_user_and_id_query(user_id, trigger_id)
      |> Repo.one()

    case user_trigger do
      %UserTrigger{} = user_trigger ->
        {:ok, trigger_in_struct(user_trigger)}

      nil ->
        {:ok, nil}
    end
  end

  def get_trigger_by_if_owner(user_id, trigger_id) do
    case by_user_and_id(user_id, trigger_id) do
      {:ok, %UserTrigger{user_id: ^user_id} = user_trigger} ->
        {:ok, user_trigger}

      _ ->
        {:error,
         "The trigger with id #{trigger_id} does not exists or does not belong to the current user"}
    end
  end

  @doc ~s"""
  Get all active triggers of a given type. Returns both public and private as it is used
  to run the alerts evaluator and not in the public API.
  """
  @spec get_all_triggers_by_type(String.t()) :: list(%__MODULE__{})
  def get_all_triggers_by_type(type) do
    from(
      ut in base_query(),
      where: trigger_type_equals?(type),
      preload: [{:user, :user_settings}, :tags]
    )
    |> Repo.all()
    |> Enum.map(&trigger_in_struct/1)
  end

  @doc ~s"""
  Get all active triggers of a given type. Returns both public and private as it is used
  to run the alerts evaluator and not in the public API.
  """
  @spec get_active_triggers_by_type(String.t()) :: list(%__MODULE__{})
  def get_active_triggers_by_type(type) do
    from(
      ut in base_query(),
      where: trigger_type_equals?(type) and trigger_active?(),
      preload: [{:user, :user_settings}, :tags]
    )
    |> Repo.all()
    |> Enum.map(&trigger_in_struct/1)
  end

  @doc ~s"""
  Check if a trigger is frozen.

  Triggers get automatically frozen after a predefined number of days if
  the user does not have a Sanbase PRO subscription. This alert restriction
  is deprecatng the restriction of having 10 free alerts with free accounts.
  """
  @spec frozen?(%__MODULE__{}) :: false | {:error, String.t()}
  def frozen?(%__MODULE__{} = user_trigger) do
    case Map.get(user_trigger.trigger, :is_frozen, false) do
      false -> false
      true -> {:error, "The trigger with id #{user_trigger.id} is frozen."}
    end
  end

  def unfreeze_user_frozen_alerts(user_id) do
    triggers_for(user_id)
    |> Enum.each(fn %__MODULE__{} = user_trigger ->
      case frozen?(user_trigger) do
        false -> :ok
        _ -> update_user_trigger(user_id, %{id: user_trigger.id, is_frozen: false})
      end
    end)
  end

  @doc ~s"""
  Create a new user trigger that is used to fire alerts.
  To create a new trigger `settings` and `title` parameters must be present
  """
  @spec create_user_trigger(%User{}, map()) ::
          {:ok, %__MODULE__{}} | {:error, String.t()} | {:error, %Ecto.Changeset{}}
  def create_user_trigger(%User{id: user_id} = _user, %{settings: settings} = params) do
    with {_, false} <- {:nil?, is_nil(settings)},
         :ok <- valid?(settings) do
      changeset = %UserTrigger{} |> create_changeset(%{user_id: user_id, trigger: params})

      case Repo.insert(changeset) do
        {:ok, ut} ->
          {:ok, _} = create_event(ut, changeset, TimelineEvent.create_public_trigger_type())

          post_create_process(ut)
          |> emit_event(:create_alert, %{})

        {:error, error} ->
          {:error, error}
      end
    else
      {:nil?, true} ->
        {:error, "Trigger structure is invalid. Key `settings` is empty."}

      {:error, error} ->
        {:error,
         "Trigger structure is invalid. Key `settings` is not valid. Reason: #{inspect(error)}"}
    end
  end

  def create_user_trigger(_, _),
    do: {:error, "Trigger structure is invalid. Key `settings` is missing."}

  @doc ~s"""
  Update an existing user trigger with a given UUID `trigger_id`.
  There are not required parameters.
  """
  @spec update_user_trigger(non_neg_integer, map()) ::
          {:ok, %__MODULE__{}} | {:error, String.t()} | {:error, Ecto.Changeset.t()}
  def update_user_trigger(user_id, %{id: trigger_id} = params)
      when is_integer(user_id) and user_id > 0 do
    settings = Map.get(params, :settings)

    with {_, :ok} <- {:valid?, valid_or_nil?(settings)},
         {_, {:ok, %__MODULE__{} = struct}} <-
           {:get_trigger, get_trigger_by_if_owner(user_id, trigger_id)} do
      update_result =
        struct
        |> update_changeset(%{trigger: clean_params(params)})
        |> Repo.update()

      case update_result do
        {:ok, ut} ->
          # Trigger a post-update process only if the settings changed
          if settings != ut.trigger.settings, do: post_update_process(ut), else: {:ok, ut}

        {:error, error} ->
          {:error, error}
      end
    else
      {:get_trigger, _} ->
        {:error,
         "Trigger with id #{trigger_id} does not exist or is not owned by the current user"}

      {:valid?, {:error, error}} ->
        {:error,
         "Trigger structure is invalid. Key `settings` is not valid. Reason: #{inspect(error)}"}
    end
  end

  def update_user_trigger(_, _),
    do: {:error, "Trigger structure is invalid. Key `id` is missing."}

  @doc ~s"""
  Remove an existing user trigger with a given UUID `trigger_id`.
  """
  @spec remove_user_trigger(%User{}, trigger_id) ::
          {:ok, %__MODULE__{}} | {:error, String.t()} | {:error, Ecto.Changeset.t()}
  def remove_user_trigger(%User{} = user, trigger_id) do
    case get_trigger_by_if_owner(user.id, trigger_id) do
      {:ok, %__MODULE__{} = user_trigger} ->
        Repo.delete(user_trigger)
        |> emit_event(:delete_alert, %{})

      {:error, error} ->
        {:error, error}
    end
  end

  @spec historical_trigger_points(%Trigger{} | map()) :: {:ok, list(any)} | {:error, String.t()}
  def historical_trigger_points(%Trigger{} = trigger) do
    Trigger.historical_trigger_points(trigger)
  end

  def historical_trigger_points(%{settings: settings} = params) do
    with {:ok, settings_struct} <- load_in_struct_if_valid(settings) do
      trigger = struct!(Trigger, params)

      Trigger.historical_trigger_points(%{trigger | settings: settings_struct})
    end
  end

  # Private functions

  defp post_create_process(%__MODULE__{} = user_trigger) do
    %{trigger: trigger} = user_trigger

    with {:ok, %settings_module{} = settings} <- load_in_struct_if_valid(trigger.settings) do
      case settings_module.post_create_process(%{trigger | settings: settings}) do
        :nochange ->
          {:ok, user_trigger}

        {:ok, trigger} ->
          user_trigger
          |> update_changeset(%{trigger: trigger |> Map.from_struct() |> clean_params()})
          |> Repo.update()

        {:error, reason} ->
          {:error,
           "Cannot create an alert because the post create processing failed. Reason: #{inspect(reason)}"}
      end
    end
  end

  defp post_update_process(%__MODULE__{} = user_trigger) do
    %{trigger: trigger} = user_trigger

    with {:ok, %settings_module{} = settings} <- load_in_struct_if_valid(trigger.settings) do
      case settings_module.post_update_process(%{trigger | settings: settings}) do
        :nochange ->
          {:ok, user_trigger}

        {:ok, trigger} ->
          user_trigger
          |> update_changeset(%{trigger: trigger |> Map.from_struct() |> clean_params()})
          |> Repo.update()

        {:error, reason} ->
          {:error,
           "Cannot update an alert because the post update processing failed. Reason: #{inspect(reason)}"}
      end
    end
  end

  defp by_user_and_id_query(nil, trigger_id) do
    from(
      ut in base_query(),
      where: ut.id == ^trigger_id and public_trigger?(),
      preload: [:featured_item, :tags]
    )
  end

  defp by_user_and_id_query(user_id, trigger_id) do
    from(
      ut in base_query(),
      where: ut.id == ^trigger_id and (public_trigger?() or ut.user_id == ^user_id),
      preload: [:featured_item, :tags]
    )
  end

  defp user_triggers_for(user_id) do
    from(ut in base_query(), where: ut.user_id == ^user_id, preload: [:featured_item, :tags])
    |> Repo.all()
    |> Enum.map(&trigger_in_struct/1)
  end

  defp public_user_triggers_for(user_id) do
    from(ut in base_query(),
      where: ut.user_id == ^user_id and public_trigger?(),
      preload: [:featured_item, :tags]
    )
    |> Repo.all()
    |> Enum.map(&trigger_in_struct/1)
  end

  defp valid_or_nil?(nil), do: :ok
  defp valid_or_nil?(trigger), do: valid?(trigger)

  defp valid?(trigger) do
    with {_, {:ok, trigger_struct}} <- {:load_in_struct?, load_in_struct_if_valid(trigger)},
         {_, true} <- {:valid?, Vex.valid?(trigger_struct)},
         {_, {:ok, _trigger_map}} <- {:map_from_struct, map_from_struct(trigger_struct)} do
      :ok
    else
      {:load_in_struct?, {:error, error}} ->
        Logger.warning("UserTrigger struct is not valid. Reason: #{inspect(error)}")
        {:error, error}

      {:valid?, false} ->
        {:ok, trigger_struct} = load_in_struct(trigger)
        errors = Vex.errors(trigger_struct)

        errors_text =
          errors
          |> Enum.map(fn {_, _, _, error} -> error end)

        Logger.warning("UserTrigger struct is not valid. Reason: #{inspect(errors_text)}")

        {:error, errors_text}

      {:map_from_struct, {:error, error}} ->
        Logger.warning("UserTrigger struct is not valid. Reason: #{inspect(error)}")

      {:error, error} ->
        {:error, error}
    end
  end

  defp create_event(user_trigger, changeset, event_type) do
    TimelineEvent.maybe_create_event_async(event_type, user_trigger, changeset)
    {:ok, user_trigger}
  end

  defp clean_params(params) do
    params
    |> Map.drop([:id])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end

  defp base_query(_opts \\ []) do
    from(ul in __MODULE__, where: ul.is_deleted != true)
  end

  defp maybe_apply_projects_filter(query, opts) do
    case Keyword.get(opts, :filter) do
      %{slugs: slugs} ->
        from(ut in query,
          where: slug_trigger_target?(slugs)
        )

      _ ->
        query
    end
  end
end
