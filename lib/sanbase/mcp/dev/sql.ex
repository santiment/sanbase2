defmodule Sanbase.MCP.Dev.SQL do
  @moduledoc """
  Runs SQL for the dev MCP tools through `Sanbase.Queries`, as the calling team member
  but with the table access of a SanAPI BUSINESS_MAX subscription, whatever the member's
  own subscriptions are.
  """

  alias Sanbase.Accounts.User
  alias Sanbase.Queries
  alias Sanbase.Queries.Executor.Result
  alias Sanbase.Queries.QueryMetadata

  @product_code "SANAPI"
  @plan_name "BUSINESS_MAX"

  @doc "The ClickHouse repo the dev MCP queries run with."
  @spec dynamic_repo() :: module()
  def dynamic_repo(), do: Queries.user_plan_to_dynamic_repo(@product_code, @plan_name)

  @doc """
  Run `sql` with `{{key}}` `parameters`. `opts` are passed to `Sanbase.Queries.run_query/4`.
  """
  @spec run(String.t(), map(), User.t(), Keyword.t()) :: {:ok, Result.t()} | {:error, String.t()}
  def run(sql, parameters, %User{} = user, opts \\ []) when is_binary(sql) do
    query = Queries.get_ephemeral_query_struct(sql, parameters || %{}, user)
    previous_repo = Process.get(:queries_dynamic_repo)
    # The executor also switches ClickhouseRepo's own dynamic repo.
    previous_clickhouse_repo = Sanbase.ClickhouseRepo.get_dynamic_repo()
    Process.put(:queries_dynamic_repo, dynamic_repo())

    try do
      case Queries.run_query(query, user, QueryMetadata.from_mcp_dev(user.id), opts) do
        {:ok, %Result{} = result} -> {:ok, result}
        {:error, error} -> {:error, error_message(error)}
      end
    rescue
      error -> {:error, Exception.message(error)}
    after
      if previous_repo,
        do: Process.put(:queries_dynamic_repo, previous_repo),
        else: Process.delete(:queries_dynamic_repo)

      Sanbase.ClickhouseRepo.put_dynamic_repo(previous_clickhouse_repo)
    end
  end

  @doc """
  The rows of `result` as maps keyed by column name, for the metadata tools.
  """
  @spec rows_as_maps(Result.t()) :: [map()]
  def rows_as_maps(%Result{columns: columns, rows: rows}) do
    Enum.map(rows, fn row -> columns |> Enum.zip(row) |> Map.new() end)
  end

  defp error_message(error) when is_binary(error), do: error
  defp error_message(error), do: inspect(error)
end
