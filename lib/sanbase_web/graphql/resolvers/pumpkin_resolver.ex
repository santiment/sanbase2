defmodule SanbaseWeb.Graphql.Resolvers.PumpkinResolver do
  alias Sanbase.Pumpkin

  def get_pumpkins(_root, _, %{context: %{auth: %{current_user: user}}}) do
    Pumpkin.get_pumpkins(user.id)
  end

  def update_pumpkins(_root, %{page: page}, %{context: %{auth: %{current_user: user}}}) do
    Pumpkin.update_pumpkins(user.id, page)
    |> case do
      {:ok, _} -> {:ok, true}
      _ -> {:ok, false}
    end
  end

  def create_pumpkin_code(_root, _, %{context: %{auth: %{current_user: user}}}) do
    Pumpkin.create_pumpkin_code(user.id)
  end

  def get_pumpkin_code(_root, _, %{context: %{auth: %{current_user: user}}}) do
    Pumpkin.get_pumpkin_code(user.id)
  end
end
