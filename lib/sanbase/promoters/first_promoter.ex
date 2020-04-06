defmodule Sanbase.Promoters.FirstPromoter do
  alias Sanbase.Promoters.FirstPromoterApi
  alias Sanbase.Auth.{User, UserSettings}

  @type promoter_args :: %{
          optional(:ref_id) => String.t(),
          optional(:coupon_code) => String.t()
        }
  @type promoter :: map()

  @spec create_promoter(%User{}, promoter_args) :: {:ok, promoter} | {:error, String.t()}
  def create_promoter(user, args) do
    with {:ok, promoter} <- FirstPromoterApi.create(user, args),
         {:ok, _} <- UserSettings.toggle_is_promoter(user, %{is_promoter: true}) do
      {:ok, promoter}
    end
  end

  @spec show_promoter(%User{}) :: {:ok, promoter} | {:error, String.t()}
  def show_promoter(%User{id: user_id}), do: FirstPromoterApi.show(user_id)
  def show_promoter(user_id), do: FirstPromoterApi.show(user_id)
end
