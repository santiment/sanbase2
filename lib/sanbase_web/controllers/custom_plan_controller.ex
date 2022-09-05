defmodule SanbaseWeb.CustomPlanController do
  use SanbaseWeb, :controller

  alias Sanbase.Webinar
  alias SanbaseWeb.Router.Helpers, as: Routes

  def index(conn, _params) do
    webinars = Webinar.list()
    render(conn, "index.html", webinars: webinars)
  end

  def new(conn, _params) do
    changeset = Webinar.new_changeset(%Webinar{})
    render(conn, "new.html", changeset: changeset)
  end

  def create(conn, %{"webinar" => params}) do
    case Webinar.create(params) do
      {:ok, webinar} ->
        conn
        |> put_flash(:info, "Webinar created successfully.")
        |> redirect(to: Routes.webinar_path(conn, :show, webinar))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html", changeset: changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    webinar = Webinar.by_id(id)
    webinar_users = Sanbase.Webinars.Registration.list_users_in_webinar(webinar.id)
    render(conn, "show.html", webinar: webinar, webinar_users: webinar_users)
  end

  def edit(conn, %{"id" => id}) do
    webinar = Webinar.by_id(id)
    changeset = Webinar.changeset(webinar, %{})
    render(conn, "edit.html", webinar: webinar, changeset: changeset)
  end

  def update(conn, %{"id" => id, "webinar" => webinar_params}) do
    webinar = Webinar.by_id(id)

    case Webinar.update(webinar, webinar_params) do
      {:ok, webinar} ->
        conn
        |> put_flash(:info, "Webinar updated successfully.")
        |> redirect(to: Routes.webinar_path(conn, :show, webinar))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "edit.html", webinar: webinar, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    webinar = Webinar.by_id(id)
    {:ok, _webinar} = Webinar.delete(webinar)

    conn
    |> put_flash(:info, "Webinar deleted successfully.")
    |> redirect(to: Routes.webinar_path(conn, :index))
  end
end
