defmodule SanbaseWeb.Admin.FaqDraftsLiveTest do
  use SanbaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Sanbase.Factory

  alias Sanbase.Knowledge.{Faq, FaqEntry}

  setup do
    user = insert(:user)
    admin_role = insert(:role_admin_panel_viewer)
    {:ok, _user_role} = Sanbase.Accounts.UserRole.create(user.id, admin_role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)
    conn = Plug.Test.init_test_session(build_conn(), jwt_tokens)

    draft =
      %FaqEntry{status: :draft, origin: :mcp}
      |> FaqEntry.changeset(%{"question" => "Q?", "answer_markdown" => "A."})
      |> Sanbase.Repo.insert!()

    {:ok, conn: conn, user: user, draft: draft}
  end

  test "a reviewer publishes a draft", %{conn: conn, user: user, draft: draft} do
    {:ok, view, _html} = live(conn, "/admin/faq/#{draft.id}")

    view |> element("#faq-publish") |> render_click()

    entry = Faq.get_entry!(draft.id)
    assert entry.status == :published
    assert entry.reviewed_by_id == user.id
  end
end
