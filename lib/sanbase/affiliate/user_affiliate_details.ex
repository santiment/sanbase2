defmodule Sanbase.Affiliate.UserAffiliateDetails do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Accounts.User
  alias Sanbase.Repo

  schema "user_affiliate_details" do
    field(:telegram_handle, :string)
    field(:marketing_channels, :string)
    belongs_to(:user, User)

    timestamps()
  end

  @doc false
  def changeset(user_affiliate_details, attrs) do
    user_affiliate_details
    |> cast(attrs, [:telegram_handle, :marketing_channels, :user_id])
    |> validate_required([:telegram_handle, :user_id])
    |> unique_constraint(:user_id)
  end

  def create(attrs \\ %{}) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  def are_user_affiliate_datails_submitted?(user_id) do
    case Repo.get_by(UserAffiliateDetails, user_id: user_id) do
      nil -> false
      _ -> true
    end
  end
end
