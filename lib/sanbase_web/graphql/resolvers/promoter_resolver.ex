defmodule SanbaseWeb.Graphql.Resolvers.PromoterResolver do
  alias Sanbase.Promoters.FirstPromoter

  def create_promoter(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    FirstPromoter.create_promoter(current_user, args)
  end

  def show_promoter(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    FirstPromoter.show_promoter(current_user)
  end
end
