defmodule SanbaseWeb.Graphql.Resolvers.PumpkinResolver do
  alias Sanbase.Pumpkin

  def get_pumpkins_count(_root, _, %{context: %{auth: %{current_user: user}}}) do
    Pumpkin.get_pumpkins_count(user.id)
  end

  def update_pumpkins(_root, %{count: count}, %{context: %{auth: %{current_user: user}}}) do
    Pumpkin.update_pumpkins(user.id, count)
    |> case do
      {:ok, _} -> {:ok, true}
      _ -> {:ok, false}
    end
  end

  def create_pumpkin_code(_root, _, %{context: %{auth: %{current_user: user}}}) do
    Pumpkin.create_pumpkin_code(user.id)
  end
end
