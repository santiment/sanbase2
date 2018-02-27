import gql from 'graphql-tag'

export const currentPollGQL = gql`{
  currentPoll {
    endAt
    posts {
      id
      title
      state
      moderationComment
      link
      createdAt
      votedAt
      totalSanVotes
      user {
        id
        username
      }
    }
    startAt
  }
}`

export default currentPollGQL
