defmodule SanbaseWeb.Graphql.AccountTest do
  use SanbaseWeb.ConnCase

  alias Sanbase.Model.Project
  alias Sanbase.Auth.User
  alias Sanbase.Repo

  import Mockery
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user =
      %User{salt: User.generate_salt()}
      |> Repo.insert!()

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn}
  end

  test "change email of current user", %{conn: conn} do
    new_email = "new_test_email@santiment.net"

    query = """
    mutation {
      changeEmail(email: "#{new_email}") {
        email
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    assert json_response(result, 200)["data"]["changeEmail"]["email"] == new_email
  end

  test "follow and unfollow a project", %{conn: conn} do
    project =
      %Project{name: "TestProjectName"}
      |> Repo.insert!()

    follow_mutation = """
    mutation {
      followProject(projectId: #{project.id}){
        followedProjects {
          id
        }
      }
    }
    """

    follow_result =
      conn
      |> post("/graphql", mutation_skeleton(follow_mutation))

    assert [%{"id" => "#{project.id}"}] ==
             json_response(follow_result, 200)["data"]["followProject"]["followedProjects"]

    unfollow_mutation = """
    mutation {
      unfollowProject(projectId: #{project.id}){
        followedProjects {
          id
        }
      }
    }
    """

    unfollow_result =
      conn
      |> post("/graphql", mutation_skeleton(unfollow_mutation))

    followed_projects =
      json_response(unfollow_result, 200)["data"]["followProject"]["followedProjects"]

    assert followed_projects == nil || [%{"ticker" => "#{project.id}"}] not in followed_projects
  end

  test "trying to login using invalid token for a user", %{conn: conn} do
    user =
      %User{salt: User.generate_salt(), email: "example@santiment.net"}
      |> Repo.insert!()

    query = """
    mutation {
      emailLoginVerify(email: "#{user.email}", token: "invalid_token") {
        user {
          email
        },
        token
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    assert json_response(result, 200)["errors"] != nil
  end

  test "trying to login with a valid email token", %{conn: conn} do
    {:ok, user} =
      %User{salt: User.generate_salt(), email: "example@santiment.net"}
      |> Repo.insert!()
      |> User.update_email_token()

    query = """
    mutation {
      emailLoginVerify(email: "#{user.email}", token: "#{user.email_token}") {
        user {
          email
        },
        token
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    loginData = json_response(result, 200)["data"]["emailLoginVerify"]

    {:ok, user} = User.find_or_insert_by_email(user.email)

    assert loginData["token"] != nil
    assert loginData["user"]["email"] == user.email
    assert Timex.diff(Timex.now(), user.email_token_validated_at, :seconds) == 0
  end

  test "trying to login with a valid email token after more than 1 day", %{conn: conn} do
    {:ok, user} =
      %User{salt: User.generate_salt(), email: "example@santiment.net"}
      |> Repo.insert!()
      |> User.update_email_token()

    user =
      user
      |> Ecto.Changeset.change(email_token_generated_at: Timex.shift(Timex.now(), days: -2))
      |> Repo.update!()

    query = """
    mutation {
      emailLoginVerify(email: "#{user.email}", token: "#{user.email_token}") {
        user {
          email
        }
        token
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    assert json_response(result, 200)["errors"] != nil
  end

  test "trying to login again with a valid email token after one validation", %{conn: conn} do
    {:ok, user} =
      %User{salt: User.generate_salt(), email: "example@santiment.net"}
      |> Repo.insert!()
      |> User.update_email_token()

    user =
      user
      |> Ecto.Changeset.change(
        email_token_generated_at: Timex.now(),
        email_token_validated_at: Timex.now()
      )
      |> Repo.update!()

    query = """
    mutation {
      emailLoginVerify(email: "#{user.email}", token: "#{user.email_token}") {
        user {
          email
        }
        token
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    loginData = json_response(result, 200)["data"]["emailLoginVerify"]

    assert loginData["token"] != nil
    assert loginData["user"]["email"] == user.email
  end

  test "trying to login again with a valid email token after it has been validated 20 min ago", %{
    conn: conn
  } do
    {:ok, user} =
      %User{salt: User.generate_salt(), email: "example@santiment.net"}
      |> Repo.insert!()
      |> User.update_email_token()

    user =
      user
      |> Ecto.Changeset.change(
        email_token_generated_at: Timex.now(),
        email_token_validated_at: Timex.shift(Timex.now(), minutes: -20)
      )
      |> Repo.update!()

    query = """
    mutation {
      emailLoginVerify(email: "#{user.email}", token: "#{user.email_token}") {
        user {
          email
        }
        token
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    assert json_response(result, 200)["errors"] != nil
  end

  test "emailLogin returns true if the login email was sent successfully", %{
    conn: conn
  } do
    mock(Sanbase.MandrillApi, :send, {:ok, %{}})

    query = """
    mutation {
      emailLogin(email: "john@example.com") {
        success
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    assert Repo.get_by(User, email: "john@example.com")

    assert json_response(result, 200)["data"]["emailLogin"]["success"]
  end
end
