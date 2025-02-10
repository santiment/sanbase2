defmodule Sanbase.Affiliate.FirstPromoter do
  @moduledoc false
  import Sanbase.Affiliate.EventEmitter, only: [emit_event: 3]

  alias Sanbase.Accounts.User
  alias Sanbase.Accounts.UserSettings
  alias Sanbase.Affiliate.FirstPromoterApi

  @type promoter_args :: %{
          optional(:ref_id) => String.t(),
          optional(:coupon_code) => String.t()
        }
  @type promoter :: map()

  @spec create_promoter(%User{}, promoter_args) :: {:ok, promoter} | {:error, String.t()}
  def create_promoter(user, args) do
    with {:ok, promoter} <- FirstPromoterApi.create(user, args),
         {:ok, _} <- UserSettings.toggle_is_promoter(user, %{is_promoter: true}) do
      emit_event({:ok, promoter}, :create_promoter, %{
        user: user,
        promoter_origin: "first_promoter"
      })

      {:ok, promoter}
    end
  end

  @spec show_promoter(%User{}) :: {:ok, promoter} | {:error, String.t()}
  def show_promoter(%User{id: user_id}), do: FirstPromoterApi.show(user_id)
  def show_promoter(user_id), do: FirstPromoterApi.show(user_id)
end
