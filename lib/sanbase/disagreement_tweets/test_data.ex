defmodule Sanbase.DisagreementTweets.TestData do
  @moduledoc """
  Development helpers for disagreement tweets: test users and simulated votes.
  """

  import Ecto.Query
  alias Sanbase.{DisagreementTweets, Repo}

  @doc """
  Creates test users for development voting testing
  """
  def create_test_users do
    test_users = [
      %{email: "expert1@test.com", username: "expert1"},
      %{email: "expert2@test.com", username: "expert2"},
      %{email: "expert3@test.com", username: "expert3"},
      %{email: "expert4@test.com", username: "expert4"},
      %{email: "expert5@test.com", username: "expert5"}
    ]

    created_users =
      Enum.map(test_users, fn user_attrs ->
        case Sanbase.Accounts.User.by_email(user_attrs.email) do
          {:error, _} ->
            attrs =
              Map.merge(user_attrs, %{
                salt: Ecto.UUID.generate(),
                privacy_policy_accepted: true,
                marketing_accepted: false
              })

            case Sanbase.Accounts.User.create(attrs, skip_registration_check: true) do
              {:ok, user} ->
                IO.puts("✅ Created test user: #{user.email}")
                user

              {:error, _} ->
                IO.puts("❌ Failed to create user: #{user_attrs.email}")
                nil
            end

          {:ok, existing_user} ->
            IO.puts("⏭️  User already exists: #{existing_user.email}")
            existing_user
        end
      end)
      |> Enum.filter(& &1)

    IO.puts("🎉 Created/found #{length(created_users)} test users")
    {:ok, created_users}
  end

  @doc """
  Simulates voting on a tweet by multiple test users to test completion functionality

  ## Options
    * `:tweet_id` - The tweet ID to vote on (required)
    * `:votes` - List of boolean values representing votes [true, false, true, true, false] (default: random)
    * `:users` - List of user IDs to vote with (default: uses test users)

  ## Examples
      # Vote with random votes
      iex> Sanbase.DisagreementTweets.TestData.simulate_votes("1234567890")
      {:ok, %{votes_created: 5, consensus: true}}

      # Vote with specific pattern
      iex> Sanbase.DisagreementTweets.TestData.simulate_votes("1234567890", votes: [true, true, true, false, false])
      {:ok, %{votes_created: 5, consensus: true}}
  """
  def simulate_votes(tweet_id, opts \\ []) do
    {:ok, test_users} = create_test_users()

    votes = Keyword.get(opts, :votes, Enum.map(1..5, fn _ -> Enum.random([true, false]) end))
    users = Keyword.get(opts, :users, test_users) |> Enum.take(5)

    case DisagreementTweets.get_by_tweet_id(tweet_id) do
      nil ->
        {:error, "Tweet not found"}

      classified_tweet ->
        # Check current vote count
        current_count = classified_tweet.classification_count

        IO.puts("🗳️  Simulating votes for tweet: #{tweet_id}")
        IO.puts("   Current votes: #{current_count}/5")

        if current_count >= 5 do
          IO.puts("   ⚠️  Tweet already has 5+ votes, no additional votes needed")

          {:ok,
           %{
             votes_created: 0,
             already_voted: 0,
             total_count: current_count,
             consensus: classified_tweet.experts_is_prediction
           }}
        else
          votes_needed = 5 - current_count
          votes_to_add = Enum.take(votes, votes_needed)
          users_to_use = Enum.take(users, votes_needed)

          IO.puts("   Adding #{votes_needed} votes to reach completion")
          IO.puts("   Votes pattern: #{inspect(votes_to_add)}")

          results =
            Enum.zip(users_to_use, votes_to_add)
            |> Enum.with_index(1)
            |> Enum.map(fn {{user, vote}, index} ->
              attrs = %{
                classified_tweet_id: classified_tweet.id,
                user_id: user.id,
                is_prediction: vote,
                classified_at: DateTime.utc_now()
              }

              case DisagreementTweets.create_classification(attrs) do
                {:ok, _classification} ->
                  IO.puts(
                    "   [#{index}/#{votes_needed}] ✅ #{user.email}: #{if vote, do: "👍 Prediction", else: "👎 Not Prediction"}"
                  )

                  :ok

                {:error, changeset} ->
                  if changeset.errors[:classified_tweet_id] do
                    IO.puts("   [#{index}/#{votes_needed}] ⏭️  #{user.email}: Already voted")
                    :already_voted
                  else
                    IO.puts(
                      "   [#{index}/#{votes_needed}] ❌ #{user.email}: Error - #{inspect(changeset.errors)}"
                    )

                    :error
                  end
              end
            end)

          votes_created = Enum.count(results, &(&1 == :ok))
          already_voted = Enum.count(results, &(&1 == :already_voted))

          # Get updated tweet to check consensus
          updated_tweet = Repo.get(DisagreementTweets.ClassifiedTweet, classified_tweet.id)

          IO.puts("")
          IO.puts("🎉 Voting simulation completed!")
          IO.puts("   ✅ New votes created: #{votes_created}")
          IO.puts("   ⏭️  Already voted: #{already_voted}")
          IO.puts("   📊 Total classifications: #{updated_tweet.classification_count}")

          if updated_tweet.experts_is_prediction != nil do
            consensus =
              if updated_tweet.experts_is_prediction, do: "PREDICTION", else: "NOT PREDICTION"

            IO.puts("   🏆 Expert Consensus: #{consensus}")
          end

          {:ok,
           %{
             votes_created: votes_created,
             already_voted: already_voted,
             total_count: updated_tweet.classification_count,
             consensus: updated_tweet.experts_is_prediction
           }}
        end
    end
  end

  @doc """
  Quick helper to test completion on the first available tweet
  """
  def test_completion(votes \\ [true, true, true, false, false]) do
    case DisagreementTweets.list_disagreement_tweets(limit: 1) do
      [tweet | _] ->
        IO.puts("🧪 Testing completion on tweet: #{tweet.tweet_id}")
        simulate_votes(tweet.tweet_id, votes: votes)

      [] ->
        IO.puts("❌ No disagreement tweets available. Create some first.")
        {:error, "No tweets available"}
    end
  end

  @doc """
  Sets up a tweet with exactly 4 votes so you can add the 5th vote through the UI

  ## Options
    * `:votes` - List of 4 boolean values for the first 4 votes (default: [true, true, false, false])
    * `:tweet_id` - Specific tweet ID to use (default: first available tweet)

  ## Examples
      # Set up with default 2-2 tie, your vote will be decisive
      iex> Sanbase.DisagreementTweets.TestData.setup_for_manual_vote()

      # Set up with 3-1 prediction lead, your vote will confirm or deny
      iex> Sanbase.DisagreementTweets.TestData.setup_for_manual_vote(votes: [true, true, true, false])

      # Set up with 1-3 not-prediction lead
      iex> Sanbase.DisagreementTweets.TestData.setup_for_manual_vote(votes: [true, false, false, false])
  """
  def setup_for_manual_vote(opts \\ []) do
    votes = Keyword.get(opts, :votes, [true, true, false, false])
    tweet_id = Keyword.get(opts, :tweet_id, nil)

    if length(votes) != 4 do
      {:error, "Must provide exactly 4 votes"}
    else
      target_tweet =
        case tweet_id do
          nil ->
            case DisagreementTweets.list_disagreement_tweets(limit: 1) do
              [tweet | _] -> tweet
              [] -> nil
            end

          id ->
            DisagreementTweets.get_by_tweet_id(id)
        end

      case target_tweet do
        nil ->
          IO.puts("❌ No disagreement tweets available. Create some first.")
          {:error, "No tweets available"}

        tweet ->
          # Clear any existing votes first
          from(tc in DisagreementTweets.TweetClassification,
            where: tc.classified_tweet_id == ^tweet.id
          )
          |> Repo.delete_all()

          # Reset counts
          from(ct in DisagreementTweets.ClassifiedTweet, where: ct.id == ^tweet.id)
          |> Repo.update_all(set: [classification_count: 0, experts_is_prediction: nil])

          IO.puts("🎮 Setting up tweet for manual voting: #{tweet.tweet_id}")
          IO.puts("   Cleared existing votes")

          # Add exactly 4 votes
          {:ok, test_users} = create_test_users()
          users_to_use = Enum.take(test_users, 4)

          results =
            Enum.zip(users_to_use, votes)
            |> Enum.with_index(1)
            |> Enum.map(fn {{user, vote}, index} ->
              attrs = %{
                classified_tweet_id: tweet.id,
                user_id: user.id,
                is_prediction: vote,
                classified_at: DateTime.utc_now()
              }

              case DisagreementTweets.create_classification(attrs) do
                {:ok, _classification} ->
                  IO.puts(
                    "   [#{index}/4] ✅ #{user.email}: #{if vote, do: "👍 Prediction", else: "👎 Not Prediction"}"
                  )

                  :ok

                {:error, reason} ->
                  IO.puts("   [#{index}/4] ❌ #{user.email}: Error - #{inspect(reason)}")
                  :error
              end
            end)

          votes_created = Enum.count(results, &(&1 == :ok))
          prediction_votes = Enum.count(votes, & &1)
          not_prediction_votes = 4 - prediction_votes

          IO.puts("")
          IO.puts("🎯 Setup complete! Current status:")

          IO.puts(
            "   📊 Votes: 4/5 (#{prediction_votes} prediction, #{not_prediction_votes} not prediction)"
          )

          IO.puts("   🔮 Your vote will be decisive!")
          IO.puts("")
          IO.puts("👉 Go to /admin/disagreement_tweets in your browser")
          IO.puts("   1. Look for tweet: #{tweet.tweet_id}")
          IO.puts("   2. It should show '4/5 votes' and be in 'Not classified by me' tab")
          IO.puts("   3. Cast your vote to see real-time consensus calculation!")

          prediction_after_true = prediction_votes + 1
          prediction_after_false = prediction_votes

          IO.puts("")
          IO.puts("🎲 Outcome preview:")

          IO.puts(
            "   If you vote 👍 Prediction: #{prediction_after_true}/5 → #{if prediction_after_true >= 3, do: "PREDICTION", else: "NOT PREDICTION"}"
          )

          IO.puts(
            "   If you vote 👎 Not Prediction: #{prediction_after_false}/5 → #{if prediction_after_false >= 3, do: "PREDICTION", else: "NOT PREDICTION"}"
          )

          {:ok,
           %{
             tweet_id: tweet.tweet_id,
             votes_setup: votes_created,
             current_prediction_votes: prediction_votes,
             current_not_prediction_votes: not_prediction_votes,
             # True if it's a 2-2 tie
             your_vote_decisive: prediction_votes == 2
           }}
      end
    end
  end

  @doc """
  Fixes tweets that have more than 5 votes by removing excess votes and recalculating consensus
  """
  def fix_overvoted_tweets do
    # Find tweets with more than 5 classifications
    overvoted_tweets =
      from(ct in DisagreementTweets.ClassifiedTweet,
        where: ct.classification_count > 5,
        select: ct
      )
      |> Repo.all()

    if Enum.empty?(overvoted_tweets) do
      IO.puts("✅ No overvoted tweets found")
      {:ok, %{fixed: 0}}
    else
      IO.puts("🔧 Found #{length(overvoted_tweets)} tweets with >5 votes, fixing...")

      fixed_count =
        Enum.map(overvoted_tweets, fn tweet ->
          # Get all classifications for this tweet, ordered by date
          classifications =
            from(tc in DisagreementTweets.TweetClassification,
              where: tc.classified_tweet_id == ^tweet.id,
              order_by: tc.classified_at,
              select: tc
            )
            |> Repo.all()

          current_count = length(classifications)
          IO.puts("   Tweet #{tweet.tweet_id}: #{current_count} votes")

          if current_count > 5 do
            # Keep first 5, remove the rest
            {keep, remove} = Enum.split(classifications, 5)

            # Delete excess classifications
            excess_ids = Enum.map(remove, & &1.id)

            from(tc in DisagreementTweets.TweetClassification, where: tc.id in ^excess_ids)
            |> Repo.delete_all()

            # Update classification count
            from(ct in DisagreementTweets.ClassifiedTweet, where: ct.id == ^tweet.id)
            |> Repo.update_all(set: [classification_count: 5])

            # Recalculate consensus
            prediction_count = Enum.count(keep, & &1.is_prediction)
            experts_is_prediction = prediction_count >= 3

            from(ct in DisagreementTweets.ClassifiedTweet, where: ct.id == ^tweet.id)
            |> Repo.update_all(set: [experts_is_prediction: experts_is_prediction])

            IO.puts(
              "     ✅ Fixed: kept first 5 votes, consensus: #{if experts_is_prediction, do: "PREDICTION", else: "NOT PREDICTION"}"
            )

            1
          else
            0
          end
        end)
        |> Enum.sum()

      IO.puts("🎉 Fixed #{fixed_count} tweets")
      {:ok, %{fixed: fixed_count}}
    end
  end
end
