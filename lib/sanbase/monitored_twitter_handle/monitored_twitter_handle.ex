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
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "monitored_twitter_handles" do
    field(:handle, :string)
    field(:notes, :string)
    field(:origin, :string)
    field(:status, :string)

    belongs_to(:user, User)

    timestamps()
  end

  def is_handle_monitored(handle) do
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
    |> change(%{handle: String.downcase(handle), user_id: user_id, origin: origin, notes: notes})
    |> validate_required([:handle, :user_id, :origin])
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

  @doc false
  def update_status(record_id, status)
      when status in ["approved", "declined", "pending_approval"] do
    # The status is updated from an admin panel
    Repo.get!(__MODULE__, record_id)
    |> change(%{status: status})
    |> Repo.update()
    |> case do
      {:ok, %__MODULE__{user_id: user_id}} = result when status == "approved" ->
        maybe_add_user_promo_code(user_id)
        result

      result ->
        result
    end
  end

  # Private functions

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

      cond do
        records_count >= 7 and codes_count <= 1 ->
          create_user_promo_code(user_id, 27)

        records_count >= 3 and codes_count == 0 ->
          create_user_promo_code(user_id, 54)

        true ->
          :ok
      end
    end
  end

  defp create_user_promo_code(user_id, percent_off) do
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
