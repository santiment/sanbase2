defmodule Sanbase.Accounts.Interaction do
  use Ecto.Schema

  @supported_entity_types [
    :project_watchlist,
    :address_watchlsit,
    :screener,
    :insight,
    :chart_configuration,
    :user_trigger
  ]

  @supported_entity_types_internal ["watchlist", "insight", "chart_configuration", "user_trigger"]

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          entity_id: non_neg_integer(),
          entity_type: String.t(),
          entity_details: Map.t(),
          interaction_type: String.t()
        }

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Accounts.User

  schema "user_entity_interactions" do
    field(:entity_id, :integer)
    field(:entity_type, :string)
    field(:entity_details, :map)
    field(:interaction_type, :string)

    belongs_to(:user, User)

    timestamps()
  end

  @doc ~s"""

  """
  @spec store_user_interaction(non_neg_integer(), Map.t()) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  def store_user_interaction(user_id, args) do
    args =
      args
      |> Map.put(:user_id, user_id)
      |> Map.put(:interaction_type, to_string(args.interaction_type))
      |> Map.put(:entity_type, deduce_entity_column_name(args.entity_type))

    %__MODULE__{}
    |> cast(args, [:entity_id, :entity_type, :entity_details, :interaction_type, :user_id])
    |> validate_change(:entity_type, &validate_entity_type/2)
    |> validate_change(:interaction_type, &validate_interaction_type/2)
    |> Sanbase.Repo.insert()
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

  def get_user_most_used_query(user_id, entity_type_or_types, opts) do
    {limit, offset} = Sanbase.Utils.Transform.opts_to_limit_offset(opts)

    entity_types =
      List.wrap(entity_type_or_types) |> Enum.map(&deduce_entity_column_name/1) |> Enum.uniq()

    from(
      row in __MODULE__,
      where: row.entity_type in ^entity_types and row.user_id == ^user_id,
      group_by: [row.entity_type, row.entity_id],
      select: %{entity_type: row.entity_type, entity_id: row.entity_id},
      order_by: [
        desc:
          fragment("""
          3 * COUNT(CASE WHEN inserted_at >= now() - INTERVAL '1 day' THEN 1 ELSE NULL END) +
          1.5 * COUNT(CASE WHEN inserted_at >= now() - INTERVAL '7 days' AND inserted_at < now() - INTERVAL '1 day' THEN 1 ELSE NULL END) +
          0.7 * COUNT(CASE WHEN inserted_at >= now() - INTERVAL '60 days' AND inserted_at < now() - INTERVAL '7 day' THEN 1 ELSE NULL END) +
          0.3 * COUNT(CASE WHEN inserted_at >= now() - INTERVAL '90 days' AND inserted_at < now() - INTERVAL '60 days' THEN 1 ELSE NULL END)
          """)
      ],
      offset: ^offset,
      limit: ^limit
    )
  end

  def deduce_entity_column_name(entity_type) do
    case entity_type do
      x when x in [:project_watchlist, :address_watchlist, :screener, :watchlist] -> "watchlist"
      x when x in [:insight, :chart_configuration, :user_trigger] -> to_string(x)
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
