defmodule Sanbase.ExAdmin.Voting.Post do
  use ExAdmin.Register

  alias Sanbase.Repo
  import Plug.Conn

  register_resource Sanbase.Voting.Post do
    member_action(:approve, &__MODULE__.approve_action/2, label: "Approve")

    def approve_action(conn, params) do
      Repo.get(Post, params[:id])
      |> Post.approve_changeset()
      |> Repo.update!()

      conn
      |> put_resp_header("location", ExAdmin.Utils.admin_resource_path(conn, :index))
      |> send_resp(302, "")
    end
  end
end
