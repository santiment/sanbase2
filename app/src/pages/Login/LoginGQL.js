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

const emailLoginGQL = gql`
  mutation emailLogin($email: String!, $username: String!, $consent: String!) {
    emailLogin(email: $email, username: $username, consent: $consent) {
      success
    }
  }
`

export {
  ethLoginGQL,
  emailLoginGQL
}
