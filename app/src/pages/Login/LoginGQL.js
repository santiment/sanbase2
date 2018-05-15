import gql from 'graphql-tag'

const ethLoginGQL = gql`
  mutation ethLogin($signature: String!, $address: String!, $messageHash: String!) {
    ethLogin(
      signature: $signature,
      address: $address,
      messageHash: $messageHash) {
        token,
        user {
          id,
          email,
          username,
          ethAccounts {
            address,
            sanBalance
          }
        }
      }
}`

const followedProjectsGQL = gql`
  query followedProjects {
    followedProjects {
        id,
      }
}`

const emailLoginGQL = gql`
  mutation emailLogin($email: String!, $username: String!) {
    emailLogin(email: $email, username: $username) {
      success
    }
  }
`

export {
  ethLoginGQL,
  followedProjectsGQL,
  emailLoginGQL
}
