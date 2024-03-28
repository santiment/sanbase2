defmodule Sanbase.MonitoredTwitterHandle do
  use Ecto.Schema

  alias Sanbase.Repo
  alias Sanbase.Accounts.User
  alias Sanbase.Billing.UserPromoCode

  import Ecto.Query
  import Ecto.Changeset

  @type t :: %__MODULE__{
          handle: String.t(),
          notes: String.t(),
          user_id: User.user_id(),
          user: User.t(),
          origin: String.t(),
          # One of approved/declined/pending_approval
          status: String.t(),
          comment: String.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @statuses ["approved", "declined", "pending_approval"]

  schema "monitored_twitter_handles" do
    field(:handle, :string)
    field(:notes, :string)
    field(:origin, :string)
    field(:status, :string)
    # moderator/admin comment when approving/declining
    field(:comment, :string)

    belongs_to(:user, User)

    timestamps()
  end

  def is_handle_monitored(handle) do
    handle = normalize_handle(handle)
    query = from(m in __MODULE__, where: m.handle == ^handle)

    {:ok, Repo.exists?(query)}
  end

  @doc ~s"""
  Add a twitter handle to monitor
  """
  @spec add_new(String.t(), User.user_id(), String.t(), String.t()) ::
          {:ok, Sanbase.MonitoredTwitterHandle.t()} | {:error, String.t()}
  def add_new(handle, user_id, origin, notes) do
    %__MODULE__{}
    |> change(%{handle: normalize_handle(handle), user_id: user_id, origin: origin, notes: notes})
    |> validate_required([:handle, :user_id, :origin])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:handle)
    |> Repo.insert()
    |> maybe_transform_error()
  end

  @doc ~s"""
  Get a list of all twitter handles that a user has submitted
  """
  @spec get_user_submissions(User.user_id()) :: {:ok, [t()]}
  def get_user_submissions(user_id) do
    query = from(m in __MODULE__, where: m.user_id == ^user_id)

    {:ok, Repo.all(query)}
  end

  # @doc false
  def update_status(record_id, status, comment \\ nil) when status in @statuses do
    # The status is updated from an admin panel
    result =
      Repo.get!(__MODULE__, record_id)
      |> change(%{status: status, comment: comment})
      |> Repo.update()

    case result do
      {:ok, %__MODULE__{user_id: user_id}} = result when status == "approved" ->
        maybe_add_user_promo_code(user_id)
        result

      result ->
        result
    end
  end

  def list_all_approved() do
    # Requested by the social data team -- do not include handles that are approved, but with a
    # comment. These could be handles that are sharing content not in english, not crypto, or
    # crypto and english, but self-promotion. The only times comments are used are to provide
    # info why the handle should not end up in our social data pipelines
    query =
      from(
        m in __MODULE__,
        where: m.status == "approved" and m.comment == ""
      )

    Repo.all(query)
  end

  def list_all_submissions() do
    query = from(m in __MODULE__, where: m.origin == "graphql_api", preload: [:user])

    Repo.all(query)
  end

  # Private functions

  defp normalize_handle(handle) do
    handle
    |> String.downcase()
    |> String.trim()
    |> String.trim_leading("@")
  end

  defp count_user_approved_submissions(user_id) do
    query = from(m in __MODULE__, where: m.user_id == ^user_id and m.status == "approved")

    {:ok, Repo.aggregate(query, :count, :id)}
  end

  defp maybe_transform_error({:ok, _} = result), do: result

  defp maybe_transform_error({:error, changeset}) do
    case Sanbase.Utils.ErrorHandling.changeset_errors(changeset) do
      %{handle: ["has already been taken"]} ->
        {:error, "The provided twitter handle is already being monitored."}

      _ ->
        msg = Sanbase.Utils.ErrorHandling.changeset_errors_string(changeset)
        {:error, msg}
    end
  end

  # During Halloween 2023, if the user has enough approved submissions,
  # they will be given a promo code for 27% or 54% off.
  @campaign "trick_or_tweet_2023"
  defp maybe_add_user_promo_code(user_id) do
    with {:ok, records_count} <- count_user_approved_submissions(user_id),
         {:ok, codes} <-
           UserPromoCode.get_total_user_promo_codes_for_campaign(user_id, @campaign) do
      # This includes all used and unused promo codes for that campaign.
      codes_count = length(codes)

      # Run the creation in 2 ifs so in case of re-issuing of promo codes,
      # we create all the necessary promo codes on one run
      if records_count >= 3 and codes_count == 0 do
        create_user_promo_code_for_campaign(user_id, 27)
      end

      if records_count >= 7 and codes_count == 1 do
        create_user_promo_code_for_campaign(user_id, 54)
      end

      :ok
    end
  end

  defp create_user_promo_code_for_campaign(user_id, percent_off) do
    redeem_by = DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second)

    {:ok, coupon} =
      Sanbase.StripeApi.create_promo_coupon(%{
        duration: "once",
        percent_off: percent_off,
        redeem_by: redeem_by |> DateTime.to_unix(),
        metadata: %{campaign: @campaign, product: "SANBASE"},
        max_redemptions: 1
      })

    UserPromoCode.create(%{
      campaign: @campaign,
      coupon: coupon.id,
      user_id: user_id,
      max_redemptions: 1,
      times_redeemed: 0,
      percent_off: percent_off,
      redeem_by: redeem_by,
      metadata: %{campaign: @campaign, product: "SANBASE"}
    })
  end
end
