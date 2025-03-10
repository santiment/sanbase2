defmodule SanbaseWeb.ReportController do
  use SanbaseWeb, :controller

  alias Sanbase.Report
  alias SanbaseWeb.Router.Helpers, as: Routes

  def index(conn, _params) do
    reports = Report.list_reports()
    render(conn, "index.html", reports: reports)
  end

  def new(conn, _params) do
    changeset = Report.new_changeset(%Report{})
    render(conn, "new.html", changeset: changeset)
  end

  def create(conn, %{
        "report" => %{"report" => report} = params
      }) do
    {params, _} = Map.split(params, ~w(name description is_published is_pro tags))
    params = Sanbase.MapUtils.atomize_keys(params)

    case Report.save_report(report, params) do
      {:ok, report} ->
        conn
        |> put_flash(:info, "Report created successfully.")
        |> redirect(to: Routes.report_path(conn, :show, report))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html", changeset: changeset)
    end
  end

  def create(conn, %{"report" => params}) do
    changeset =
      Report.changeset(%Report{}, params)
      |> Ecto.Changeset.add_error(:report, "No file uploaded!")

    render(conn, "new.html", changeset: changeset, errors: [report: "No file uploaded!"])
  end

  def show(conn, %{"id" => id}) do
    report = Report.by_id(id)
    render(conn, "show.html", report: report)
  end

  def edit(conn, %{"id" => id}) do
    report = Report.by_id(id) |> stringify_tags()
    changeset = Report.changeset(report, %{})
    render(conn, "edit.html", report: report, changeset: changeset)
  end

  def update(conn, %{"id" => id, "report" => report_params}) do
    report = Report.by_id(id)

    case Report.update(report, report_params) do
      {:ok, report} ->
        conn
        |> put_flash(:info, "Report updated successfully.")
        |> redirect(to: Routes.report_path(conn, :show, report))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "edit.html", report: report, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    report = Report.by_id(id)
    {:ok, _report} = Report.delete(report)

    conn
    |> put_flash(:info, "Report deleted successfully.")
    |> redirect(to: Routes.report_path(conn, :index))
  end

  defp stringify_tags(%Report{tags: tags} = report) do
    %{report | tags: tags |> Enum.join(", ")}
  end
end
