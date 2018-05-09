import React, { Fragment } from 'react'
import { connect } from 'react-redux'
import { graphql, withApollo } from 'react-apollo'
import GoogleAnalytics from 'react-ga'
import Raven from 'raven-js'
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
import { savePrevAuthProvider } from './../../utils/localStorage'
import metamaskDownloadImg from './../../assets/download-metamask.png'

const EthLogin = ({
  user,
  requestAuth,
  checkMetamask,
  authWithSAN,
  client,
  consent
}) => {
  return (
    <Fragment>
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
          pending={user.isLoading}
          error={user.error}
          handleAuth={() => requestAuth(user.account, authWithSAN, client, consent)} />}
    </Fragment>
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
    requestAuth: (address, authWithSAN, client, consent) => {
      signMessage(address).then(({messageHash, signature}) => {
        dispatch({
          type: 'PENDING_LOGIN'
        })
        authWithSAN({variables: { signature, address, messageHash }})
        .then(({ data }) => {
          const { token, user } = data.ethLogin
          savePrevAuthProvider('metamask')
          GoogleAnalytics.event({
            category: 'User',
            action: 'Success login with metamask'
          })
          dispatch({
            type: 'SUCCESS_LOGIN',
            token,
            user,
            consent,
          })
          client.resetStore()
          
          if (consent) {
            const consentUrl = `/consent?consent=${consent}&token=${token}`;
            window.location.replace(consentUrl);
          }
        }).catch((error) => {
          dispatch({
            type: 'FAILED_LOGIN',
            errorMessage: error
          })
          Raven.captureException(error)
        })
      }).catch(error => {
        // TODO: 2017-12-05 16:05 | Yura Zatsepin:
        // Remove console.error.
        // Added User denied, Account error messages in UI
        console.log(error)
        GoogleAnalytics.event({
          category: 'User',
          action: 'User denied login with metamask'
        })
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
    name: 'authWithSAN'
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
