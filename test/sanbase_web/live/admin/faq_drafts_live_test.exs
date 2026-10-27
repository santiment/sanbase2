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

    author = insert(:user, email: "support@santiment.net")

    draft =
      %FaqEntry{status: :draft, origin: :mcp, created_by_id: author.id}
      |> FaqEntry.changeset(%{
        "question" => "How do I rotate my API key?",
        "answer_markdown" => "Generate a new key in Account settings.",
        "internal_notes" => "Confirmed by the backend team."
      })
      |> Sanbase.Repo.insert!()

    published =
      %FaqEntry{}
      |> FaqEntry.changeset(%{"question" => "What is MVRV?", "answer_markdown" => "A ratio."})
      |> Sanbase.Repo.insert!()

    {:ok, conn: conn, user: user, draft: draft, published: published}
  end

  test "the Drafts tab lists only drafts", %{conn: conn, draft: draft, published: published} do
    {:ok, view, _html} = live(conn, "/admin/faq?status=draft")

    assert has_element?(view, "#faq-entry-#{draft.id}")
    refute has_element?(view, "#faq-entry-#{published.id}")
    assert has_element?(view, "#faq-tab-draft", "1")
  end

  test "a reviewer publishes a draft", %{conn: conn, user: user, draft: draft} do
    {:ok, view, _html} = live(conn, "/admin/faq/#{draft.id}")

    assert has_element?(view, "#faq-draft-banner", "support@santiment.net")
    assert has_element?(view, "#faq-internal-notes", "Confirmed by the backend team.")

    view |> element("#faq-publish") |> render_click()

    entry = Faq.get_entry!(draft.id)
    assert entry.status == :published
    assert entry.reviewed_by_id == user.id
    refute has_element?(view, "#faq-draft-banner")
    refute has_element?(view, "#faq-publish")
  end

  test "a draft edited after the page loaded is not published", %{conn: conn, draft: draft} do
    {:ok, view, _html} = live(conn, "/admin/faq/#{draft.id}")

    {:ok, _} =
      Sanbase.Mock.prepare_mock2(
        &Sanbase.AI.Embedding.generate_embeddings/2,
        {:ok, [List.duplicate(0.1, 1536)]}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        Faq.update_draft(draft, %{answer_markdown: "Edited by Claude after the review."})
      end)

    view |> element("#faq-publish") |> render_click()

    assert Faq.get_entry!(draft.id).status == :draft
    # The page now shows the current version for another review.
    assert render(view) =~ "Edited by Claude after the review."
    assert has_element?(view, "#faq-publish")
  end
end
