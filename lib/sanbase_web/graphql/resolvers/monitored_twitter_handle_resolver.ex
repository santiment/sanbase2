defmodule SanbaseWeb.Graphql.Resolvers.MonitoredTwitterHandleResolver do
  def is_twitter_handle_monitored(_root, %{twitter_handle: handle}, _resolution) do
    Sanbase.MonitoredTwitterHandle.is_handle_monitored(handle)
  end

  def add_twitter_handle_to_monitor(_root, args, %{context: %{auth: %{current_user: user}}}) do
    result =
      Sanbase.MonitoredTwitterHandle.add_new(
        args[:twitter_handle],
        user.id,
        "graphql_api",
        args[:notes]
      )

    case result do
      {:ok, _} -> {:ok, true}
      {:error, error_msg} -> {:error, error_msg}
    end
  end
end
