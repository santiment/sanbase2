defmodule Sanbase.Accounts.Interaction do
  @moduledoc ~s"""
  User-Entity interactions are recorded and used to suggest content to the users.

  User interactions can be used to automatically built a list of most used entities
  for every user. In the future, it can be used in a recomender system to suggest
  content that has not yet been seen.
  """
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Accounts.User
  # The same [:user_id, :entity_id, :entity_type, :interaction_type] cannot be stored
  # more than once per coooldown period. This helps avoid storing the same interaction
  # multiple times in case of browser reload, opening the entity in multiple tabs, etc.
  # This value is set to 0 in test env, so the interactions can be stored without mocking
  # the DateTime module.
  @interaction_cooldown_seconds Application.compile_env(
                                  :sanbase,
                                  [__MODULE__, :interaction_cooldown_seconds],
                                  10
                                )

  @datetime_module Application.compile_env(
                     :sanbase,
                     [__MODULE__, :datetime_module],
                     DateTime
                   )

  @supported_entity_types [
    :address_watchlist,
    :chart_configuration,
    :dashboard,
    :insight,
    :project_watchlist,
    :screener,
    :user_trigger
  ]

  @supported_entity_types_internal [
    "watchlist",
    "insight",
    "chart_configuration",
    "user_trigger",
    "dashboard"
  ]

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          entity_id: non_neg_integer(),
          entity_type: String.t(),
          user_id: non_neg_integer(),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  schema "user_entity_interactions" do
    field(:entity_id, :integer)
    field(:entity_type, :string)
    field(:interaction_type, :string)

    belongs_to(:user, User)

    timestamps()
  end

  def changeset(%__MODULE__{} = interaction, args) do
    interaction
    # cast the `:inserted_at` and `:updated_at` as the datetime is rounded
    # so the same interaction cannot be submitted multiple times in the span of
    # a few seconds (browser reload, open the same entity in multiple tabs fast, etc.)
    |> cast(args, [
      :entity_id,
      :entity_type,
      :interaction_type,
      :user_id,
      :inserted_at,
      :updated_at
    ])
    |> validate_change(:entity_type, &validate_entity_type/2)
    |> validate_change(:interaction_type, &validate_interaction_type/2)
  end

  @doc ~s"""
  Store a user-entity interaction that represents a view/comment/vote/etc.

  The entity_type is converted to its internal representation before storing.
  This means that all types of watchlists are stored as `watchlist`.
  """
  @spec store_user_interaction(non_neg_integer(), Map.t()) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  def store_user_interaction(user_id, args) do
    inserted_at =
      @datetime_module.utc_now()
      |> Sanbase.DateTimeUtils.round_datetime(
        second: @interaction_cooldown_seconds,
        rounding: :down
      )
      |> @datetime_module.to_naive()

    args =
      args
      |> Map.merge(%{
        user_id: user_id,
        inserted_at: inserted_at,
        updated_at: inserted_at,
        interaction_type: to_string(args.interaction_type),
        entity_type: deduce_entity_column_name(args.entity_type)
      })

    %__MODULE__{}
    |> changeset(args)
    |> Sanbase.Repo.insert(on_conflict: :nothing)
  end

  @doc ~s"""
  Return the most used entities of the given type for the user.
  The usage rank is based on the number of times the entity was used/viewed. More recent
  views contributred more to the score compared to old usage.

  In the future, the interaction type can be weighted differently - 1 for view, 5 for like, etc.
  """
  @spec get_user_most_used(non_neg_integer(), String.t() | list(String.t()), Keyword.t()) ::
          {:ok, list(t())}
  def get_user_most_used(user_id, entity_type_or_types, opts) do
    get_user_most_used_query(user_id, entity_type_or_types, opts)
    |> Sanbase.Repo.all()
  end

  @weight_1d_to_now 2.0
  @weight_7d_to_1d 1.5
  @weight_30d_to_7d 1.0
  @weight_60d_to_30d 0.8
  @weight_90d_to_60d 0.6

  @doc ~s"""
  Return the Ecto query for fetching the most used entities.
  It is public as it's used in the Entity module.
  """
  @spec get_user_most_used_query(
          non_neg_integer(),
          Entity.entity_type() | list(Entity.entity_type()),
          Keyword.t()
        ) :: Ecto.Query.t()
  def get_user_most_used_query(user_id, entity_type_or_types, opts) do
    {limit, offset} = Sanbase.Utils.Transform.opts_to_limit_offset(opts)

    entity_types =
      List.wrap(entity_type_or_types) |> Enum.map(&deduce_entity_column_name/1) |> Enum.uniq()

    from(
      row in __MODULE__,
      where:
        row.entity_type in ^entity_types and row.user_id == ^user_id and
          row.interaction_type == "view",
      group_by: [row.entity_type, row.entity_id],
      select: %{entity_type: row.entity_type, entity_id: row.entity_id},
      order_by: [
        # Subtract 1 from every counter to remove entities that are opened just once
        desc:
          fragment(
            """
            ?::float * GREATEST(0, COUNT(CASE WHEN inserted_at >= now() - INTERVAL '1 day' THEN 1 ELSE NULL END) - 1) +
            ?::float * GREATEST(0, COUNT(CASE WHEN inserted_at >= now() - INTERVAL '7 days' AND inserted_at < now() - INTERVAL '1 day' THEN 1 ELSE NULL END) - 1) +
            ?::float * GREATEST(0, COUNT(CASE WHEN inserted_at >= now() - INTERVAL '30 days' AND inserted_at < now() - INTERVAL '7 day' THEN 1 ELSE NULL END) - 1) +
            ?::float * GREATEST(0, COUNT(CASE WHEN inserted_at >= now() - INTERVAL '60 days' AND inserted_at < now() - INTERVAL '30 day' THEN 1 ELSE NULL END) - 1) +
            ?::float * GREATEST(0, COUNT(CASE WHEN inserted_at >= now() - INTERVAL '90 days' AND inserted_at < now() - INTERVAL '60 days' THEN 1 ELSE NULL END) - 1)
            """,
            ^@weight_1d_to_now,
            ^@weight_7d_to_1d,
            ^@weight_30d_to_7d,
            ^@weight_60d_to_30d,
            ^@weight_90d_to_60d
          )
      ],
      offset: ^offset,
      limit: ^limit
    )
  end

  @watchlist_entities [:project_watchlist, :address_watchlist, :screener, :watchlist]
  def deduce_entity_column_name(entity_type) when entity_type in @supported_entity_types do
    case entity_type do
      x when x in @watchlist_entities -> "watchlist"
      x -> to_string(x)
    end
  end

  defp validate_entity_type(_changeset, entity_type) do
    case entity_type in @supported_entity_types_internal do
      true -> []
      false -> [{:entity_type, "Unsupported entity type #{entity_type}"}]
    end
  end

  defp validate_interaction_type(_changeset, interaction_type) do
    case interaction_type in ["view", "upvote", "downvote", "comment"] do
      true -> []
      false -> [{:entity_type, "Unsupported interaction type #{interaction_type}"}]
    end
  end
end
