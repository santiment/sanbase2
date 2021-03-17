defmodule Sanbase.Accounts do
  alias __MODULE__.User

  def get_user(user_id_or_ids) do
    User.by_id(user_id_or_ids)
  end
end
