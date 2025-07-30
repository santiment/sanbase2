defmodule SanbaseWeb.Graphql.SocialDataApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.SocialData

  @error_response "Error executing query. See logs for details."

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn}
  end

  describe "word context" do
    test "successfully fetch word context", context do
      success_response = [
        %{score: 1.0, word: "mas"},
        %{score: 0.7688603531300161, word: "christ"},
        %{score: 0.7592295345104334, word: "christmas"}
      ]

      with_mock SocialData, word_context: fn _, _, _, _, _ -> {:ok, success_response} end do
        args = %{
          word: "merry",
          source: "TELEGRAM",
          from: "2018-01-09T00:00:00Z",
          to: "2018-01-10T00:00:00Z",
          size: 1
        }

        query = word_context_query(args)
        result = execute_and_parse_success_response(context.conn, query, "wordContext")

        assert result == %{
                 "data" => %{
                   "wordContext" => [
                     %{"score" => 1.0, "word" => "mas"},
                     %{"score" => 0.7688603531300161, "word" => "christ"},
                     %{"score" => 0.7592295345104334, "word" => "christmas"}
                   ]
                 }
               }
      end
    end

    test "fetch word context - proper error is returned", context do
      with_mock SocialData, word_context: fn _, _, _, _, _ -> {:error, @error_response} end do
        args = %{
          word: "merry",
          source: "TELEGRAM",
          from: "2018-01-09T00:00:00Z",
          to: "2018-01-10T00:00:00Z",
          size: 1
        }

        query = word_context_query(args)
        error = execute_and_parse_error_response(context.conn, query, "wordContext")
        assert error =~ @error_response
      end
    end
  end

  defp word_context_query(args) do
    """
    {
      wordContext(
        word: "#{args.word}",
        source: #{args.source},
        from: "#{args.from}",
        to: "#{args.to}",
        size: #{args.size}
      ) {
        word
        score
      }
    }
    """
  end

  defp execute_and_parse_success_response(conn, query, query_name) do
    conn
    |> post("/graphql", query_skeleton(query, query_name))
    |> json_response(200)
  end

  defp execute_and_parse_error_response(conn, query, query_name) do
    conn
    |> post("/graphql", query_skeleton(query, query_name))
    |> json_response(200)
    |> Map.get("errors")
    |> hd()
    |> Map.get("message")
  end
end
