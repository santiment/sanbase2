defmodule SanbaseWeb.Graphql.AccountTest do
  use SanbaseWeb.ConnCase

  alias Sanbase.Model.Project
  alias Sanbase.Auth.User
  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user =
      %User{salt: User.generate_salt()}
      |> Repo.insert!()

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn}
  end

  test "change email of current user", context do
    new_email = "new_test_email@santiment.net"

    query = """
    mutation {
      changeEmail(email: "#{new_email}") {
        email
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", mutation_skeleton(query))

    assert json_response(result, 200)["data"]["changeEmail"]["email"] == new_email
  end

  test "follow and unfollow a project", context do
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
      context.conn
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
      context.conn
      |> post("/graphql", mutation_skeleton(unfollow_mutation))

    followed_projects =
      json_response(unfollow_result, 200)["data"]["followProject"]["followedProjects"]

    assert followed_projects == nil || [%{"ticker" => "#{project.id}"}] not in followed_projects
  end

  test "trying to login using invalid token for a user", context do
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
      context.conn
      |> post("/graphql", mutation_skeleton(query))

    assert json_response(result, 200)["errors"] != nil
  end

  test "trying to login with a valid email token", context do
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
      context.conn
      |> post("/graphql", mutation_skeleton(query))

    loginData = json_response(result, 200)["data"]["emailLoginVerify"]

    assert loginData["token"] != nil
    assert loginData["user"]["email"] == user.email
  end

  test "trying to login with a valid email token after more than 1 day", context do
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
      context.conn
      |> post("/graphql", mutation_skeleton(query))

    assert json_response(result, 200)["errors"] != nil
  end
end
