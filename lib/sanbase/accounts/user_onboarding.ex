defmodule Sanbase.Accounts.UserOnboarding do
  @moduledoc """
  Stores answers from the 4-step onboarding questionnaire shown to users
  right after they confirm their email.

  See the Notion task "Questionnaire for Sanbase" for the full design.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Accounts.User
  alias Sanbase.Repo

  @titles ~w(crypto_trader researcher content_maker new_in_crypto)
  @goals ~w(catch_trends make_better_trade_entries build_analysis understand_whats_going_on)
  @used_tools ~w(price_charts screeners on_chain_analytics social_signals news_feeds none_of_the_above)
  @behaviour_analysis_answers ~w(yes no not_sure)

  def allowed_titles, do: @titles
  def allowed_goals, do: @goals
  def allowed_used_tools, do: @used_tools
  def allowed_behaviour_analysis_answers, do: @behaviour_analysis_answers

  @type t :: %__MODULE__{
          user_id: non_neg_integer(),
          title: String.t() | nil,
          goal: String.t() | nil,
          used_tools: [String.t()],
          uses_behaviour_analysis: String.t() | nil,
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  schema "user_onboardings" do
    belongs_to(:user, User)
    field(:title, :string)
    field(:goal, :string)
    field(:used_tools, {:array, :string}, default: [])
    field(:uses_behaviour_analysis, :string)

    timestamps()
  end

  def changeset(%__MODULE__{} = struct, attrs) do
    struct
    |> cast(attrs, [:user_id, :title, :goal, :used_tools, :uses_behaviour_analysis])
    |> validate_required([:user_id])
    |> validate_inclusion(:title, @titles)
    |> validate_inclusion(:goal, @goals)
    |> validate_subset(:used_tools, @used_tools)
    |> validate_inclusion(:uses_behaviour_analysis, @behaviour_analysis_answers)
    |> unique_constraint(:user_id)
  end

  def for_user(user_id) do
    Repo.get_by(__MODULE__, user_id: user_id)
  end

  def upsert(user_id, attrs) do
    struct =
      case for_user(user_id) do
        nil -> %__MODULE__{}
        existing -> existing
      end

    struct
    |> changeset(Map.put(attrs, :user_id, user_id))
    |> Repo.insert_or_update()
  end
end
