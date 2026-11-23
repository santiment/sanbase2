defmodule Sanbase.MCP.Dev.Server do
  @moduledoc """
  Team-only MCP server for development and data exploration, served at `/mcp_dev`:
  read-only ClickHouse SQL with the BUSINESS_MAX plan's table access, and raw social
  messages from metrics-hub.

  `handle_request/2` re-checks access so a routing mistake cannot expose it.
  """

  use Anubis.Server,
    name: "santiment-dev",
    version: "1.0.0",
    capabilities: [:tools]

  alias Sanbase.MCP.Auth
  alias Sanbase.MCP.Dev.Access
  alias Sanbase.RequestContext

  component(Sanbase.MCP.Dev.ListTablesTool)
  component(Sanbase.MCP.Dev.DescribeTablesTool)
  component(Sanbase.MCP.Dev.ExecuteSqlTool)
  component(Sanbase.MCP.Dev.SocialMessagesTool)
  component(Sanbase.MCP.Dev.TweetsByAuthorTool)

  @impl true
  def server_instructions() do
    """
    Santiment's internal dev tools for the team.

    ClickHouse SQL (read-only, with the access of a SanAPI BUSINESS_MAX subscription):
    1. `list_tables` to find tables (optionally filtered by a name substring).
    2. `describe_tables` for the columns, types and sorting keys of the tables you will use.
    3. `execute_sql` to run a query. Filter on the sorting key columns, always add a LIMIT,
       and prefer aggregates over raw rows. Parameters use the `{{name}}` syntax.

    Social data: `social_messages` returns a stratified sample of raw social posts about a
    coin plus a stats block computed over all matching posts. `tweets_by_author` returns
    every indexed post by one X account in a window (only accounts Santiment tracks).
    Both can return large results: process them from a file or with a cheaper model.
    """
  end

  @impl true
  def init(_client_info, %Anubis.Server.Frame{} = frame) do
    {:ok, assign_current_user(frame)}
  end

  @impl true
  def handle_request(%{"method" => method} = request, %Anubis.Server.Frame{} = frame) do
    frame = assign_current_user(frame)

    if Access.allowed?(frame.assigns[:current_user]) or method == "ping" do
      with_request_context(frame, fn ->
        Anubis.Server.Handlers.handle(request, __MODULE__, frame)
      end)
    else
      {:error, Anubis.MCP.Error.protocol(:invalid_request, %{message: Access.denied_message()}),
       frame}
    end
  end

  # Seed the request context so ClickHouse queries carry the member's user_id in
  # log_comment, and so the masking for users with hidden activity traces applies.
  # The saved metadata is restored (not merged) so nothing leaks to the next request.
  defp with_request_context(frame, fun) do
    old_metadata = Logger.metadata()
    RequestContext.put_logger_metadata(RequestContext.from_mcp_frame(frame))

    try do
      fun.()
    after
      Logger.reset_metadata(old_metadata)
    end
  end

  defp assign_current_user(%Anubis.Server.Frame{} = frame) do
    headers = frame.context.headers || []
    user = frame.assigns[:current_user] || Auth.headers_list_to_user(headers)

    frame
    |> assign(:current_user, user)
    |> assign(:is_authenticated, not is_nil(user))
  end
end
