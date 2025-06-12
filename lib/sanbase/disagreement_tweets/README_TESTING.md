# Testing the 5-Vote Completion Feature

Since you don't have 5 user accounts in development, use these helper functions to test the completion functionality:

## Quick Setup & Testing

1. **Start IEx Console**:
```bash
iex -S mix
```

2. **Create some test tweets** (if needed):
```elixir
# Populate some test tweets first
Sanbase.DisagreementTweets.TestData.populate(size: 5)
```

3. **Test completion with default vote pattern** (3 true, 2 false = prediction):
```elixir
# This will test on the first available tweet with a 3-2 vote pattern
Sanbase.DisagreementTweets.TestData.test_completion()
```

4. **Test completion with custom vote pattern**:
```elixir
# Test with 2-3 vote pattern (majority says NOT prediction)
Sanbase.DisagreementTweets.TestData.test_completion([true, false, false, false, true])

# Test with 4-1 vote pattern (strong prediction consensus)  
Sanbase.DisagreementTweets.TestData.test_completion([true, true, true, true, false])
```

5. **Test on specific tweet**:
```elixir
# If you know a specific tweet ID
Sanbase.DisagreementTweets.TestData.simulate_votes("your_tweet_id_here", votes: [true, true, false, true, false])
```

## What the Test Functions Do

- **Creates 5 test users**: `expert1@test.com` through `expert5@test.com`
- **Simulates votes**: Each test user votes according to your specified pattern
- **Calculates consensus**: When 5th vote is cast, automatically sets `experts_is_prediction`
- **Shows results**: Displays voting progress and final consensus

## Expected Output

```
🧪 Testing completion on tweet: 1234567890
🗳️  Simulating votes for tweet: 1234567890
   Votes pattern: [true, true, true, false, false]
   [1/5] ✅ expert1@test.com: 👍 Prediction
   [2/5] ✅ expert2@test.com: 👍 Prediction  
   [3/5] ✅ expert3@test.com: 👍 Prediction
   [4/5] ✅ expert4@test.com: 👎 Not Prediction
   [5/5] ✅ expert5@test.com: 👎 Not Prediction

🎉 Voting simulation completed!
   ✅ New votes created: 5
   ⏭️  Already voted: 0
   📊 Total classifications: 5
   🏆 Expert Consensus: PREDICTION
```

## Viewing Results in UI

After running the test functions:

1. Go to `/admin/disagreement_tweets` in your browser
2. Switch to "Classified by me" tab to see the votes
3. Switch to "Completed (5 people classified)" tab to see completed tweets
4. You'll see:
   - Individual votes with user emails
   - Vote progress (5/5 votes)
   - Expert consensus result

## Clean Up (Optional)

The test users and votes will persist in your development database. If you want to clean up:

```elixir
# Delete test classifications (this will recalculate counts)
Sanbase.Repo.delete_all(Sanbase.DisagreementTweets.TweetClassification)

# Or delete test users entirely
test_emails = ["expert1@test.com", "expert2@test.com", "expert3@test.com", "expert4@test.com", "expert5@test.com"]
Enum.each(test_emails, fn email ->
  case Sanbase.Accounts.User.by_email(email) do
    {:ok, user} -> Sanbase.Repo.delete(user)
    _ -> :ok
  end
end)
``` 