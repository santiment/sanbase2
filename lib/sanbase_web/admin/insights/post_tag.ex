defmodule SanbaseWeb.ExAdmin.Insight.PostTag do
  use ExAdmin.Register

  import Ecto.Query

  register_resource Sanbase.Insight.PostTag do
    controller do
      after_filter(:set_defaults, only: [:new])
    end
  end

  def set_defaults(conn, params, resource, :new) do
    {conn, params, resource |> set_post_default(params)}
  end

  defp set_post_default(%{post_id: nil} = post_tag, params) do
    Map.get(params, :post_id, nil)
    |> case do
      nil -> post_tag
      post_id -> Map.put(post_tag, :post_id, post_id)
    end
  end
end
