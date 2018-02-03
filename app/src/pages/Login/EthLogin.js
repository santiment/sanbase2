import React from 'react'
import { connect } from 'react-redux'
import { graphql, withApollo } from 'react-apollo'
import gql from 'graphql-tag'
import {
  lifecycle,
  compose
} from 'recompose'
import { Message } from 'semantic-ui-react'
import {
  setupWeb3,
  hasMetamask,
  signMessage
} from '../../web3Helpers'
import AuthForm from './AuthForm'
import metamaskDownloadImg from './../../assets/download-metamask.png'

const EthLogin = ({
  user,
  requestAuth,
  checkMetamask,
  authWithSAN,
  client
}) => {
  return (
    <div>
      {user.isLoading && !user.hasMetamask && <div>Loading</div>}
      {!user.hasMetamask && !user.isLoading &&
        <Message warning>
          <h4>We can't detect Metamask!</h4>
          <p>We can auth you with Metamask account. It's secure and easy.</p>
          <div className='help-links'>
            <a
              target='_blank'
              rel='noopener noreferrer'
              href='https://metamask.io/#how-it-works'>How Metamask works?</a>
            <a href='https://metamask.io/'>
              <img width={128} src={metamaskDownloadImg} alt='Metamask link' />
            </a>
          </div>
        </Message>
      }
      {user.hasMetamask && !user.token &&
        <AuthForm
          account={user.account}
          handleAuth={() => requestAuth(user.account, authWithSAN, client)} />}
    </div>
  )
}

const mapStateToProps = state => {
  return {
    user: state.user
  }
}

const mapDispatchToProps = dispatch => {
  return {
    checkMetamask: hasMetamask => {
      dispatch({
        type: 'CHECK_WEB3_PROVIDER',
        hasMetamask
      })
    },
    requestAuth: (address, authWithSAN, client) => {
      signMessage(address).then(({messageHash, signature}) => {
        authWithSAN({variables: { signature, address, messageHash }})
        .then(({ data }) => {
          const { token, user } = data.ethLogin
          dispatch({
            type: 'SUCCESS_LOGIN',
            token,
            user
          })
          client.resetStore()
        }).catch((error) => {
          dispatch({
            type: 'FAILED_LOGIN',
            errorMessage: error
          })
          throw new Error(error)
        })
      }).catch(error => {
        // TODO: 2017-12-05 16:05 | Yura Zatsepin:
        // Remove console.error.
        // Added User denied, Account error messages in UI
        console.log(error)
        dispatch({
          type: 'FAILED_LOGIN',
          errorMessage: error
        })
      })
    },
    changeAccount: account => {
      dispatch({
        type: 'INIT_WEB3_ACCOUNT',
        account
      })
    }
  }
}

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

export default compose(
  connect(
    mapStateToProps,
    mapDispatchToProps
  ),
  withApollo,
  graphql(ethLoginGQL, {
    name: 'authWithSAN',
    options: { fetchPolicy: 'network-only' }
  }),
  lifecycle({
    componentDidMount () {
      this.props.checkMetamask(hasMetamask())
      setupWeb3((error, account) => {
        if (!error && this.props.account !== account) {
          this.props.changeAccount(account)
        }
      })
    }
  })
)(EthLogin)
