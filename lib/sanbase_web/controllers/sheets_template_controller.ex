defmodule SanbaseWeb.SheetsTemplateController do
  use SanbaseWeb, :controller

  alias Sanbase.SheetsTemplate
  alias SanbaseWeb.Router.Helpers, as: Routes

  def index(conn, _params) do
    sheets_templates = SheetsTemplate.list()
    render(conn, "index.html", sheets_templates: sheets_templates)
  end

  def new(conn, _params) do
    changeset = SheetsTemplate.new_changeset(%SheetsTemplate{})
    render(conn, "new.html", changeset: changeset)
  end

  def create(conn, %{"sheets_template" => params}) do
    case SheetsTemplate.create(params) do
      {:ok, sheets_template} ->
        conn
        |> put_flash(:info, "SheetsTemplate created successfully.")
        |> redirect(to: Routes.sheets_template_path(conn, :show, sheets_template))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html", changeset: changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    sheets_template = SheetsTemplate.by_id(id)
    render(conn, "show.html", sheets_template: sheets_template)
  end

  def edit(conn, %{"id" => id}) do
    sheets_template = SheetsTemplate.by_id(id)
    changeset = SheetsTemplate.changeset(sheets_template, %{})
    render(conn, "edit.html", sheets_template: sheets_template, changeset: changeset)
  end

  def update(conn, %{"id" => id, "sheets_template" => sheets_template_params}) do
    sheets_template = SheetsTemplate.by_id(id)

    case SheetsTemplate.update(sheets_template, sheets_template_params) do
      {:ok, sheets_template} ->
        conn
        |> put_flash(:info, "SheetsTemplate updated successfully.")
        |> redirect(to: Routes.sheets_template_path(conn, :show, sheets_template))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "edit.html", sheets_template: sheets_template, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    sheets_template = SheetsTemplate.by_id(id)
    {:ok, _sheets_template} = SheetsTemplate.delete(sheets_template)

    conn
    |> put_flash(:info, "SheetsTemplate deleted successfully.")
    |> redirect(to: Routes.sheets_template_path(conn, :index))
  end
end
