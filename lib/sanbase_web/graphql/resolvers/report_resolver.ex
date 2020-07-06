defmodule SanbaseWeb.Graphql.Resolvers.ReportResolver do
  require Logger

  alias Sanbase.FileStore
  alias Sanbase.Utils.FileHash
  alias Sanbase.Report

  def upload_report(_root, %{report: report}, _resolution) do
    report = %{report | filename: milliseconds_str() <> "_" <> report.filename}
    save_file(report)
  end

  def list_reports(_root, _args, _resolution) do
    user = Repo.get(Sanbase.Auth.User, 31)
    subscription = Sanbase.Billing.Subscription.current_subscription(user, @product_sanbase)

    {:ok, Report.list_published_reports(subscription)}
  end

  defp save_file(%Plug.Upload{filename: file_name} = arg) do
    with {:ok, content_hash} <- FileHash.calculate(arg.path),
         {:ok, file_name} <- FileStore.store({arg, content_hash}),
         file_url <- FileStore.url({file_name, content_hash}),
         {:ok, report} <- Report.save(%{url: file_url}) do
      {:ok, report.url}
    else
      {:error, reason} ->
        Logger.error("Could not save file: #{file_name}. Reason: #{inspect(reason)}")
        {:error, "Could not save file: #{file_name}."}
    end
  end

  defp milliseconds_str() do
    DateTime.utc_now()
    |> DateTime.to_unix(:millisecond)
    |> Integer.to_string()
  end
end
