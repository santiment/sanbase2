import gql from 'graphql-tag'

export const currentPollGQL = gql`{
  allInsights {
    id
    title
    state
    moderationComment
    createdAt
    votedAt
    totalSanVotes
    user {
      id
      username
    }
  }
}`

export default currentPollGQL
