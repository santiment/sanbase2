import React from 'react'
import { Redirect } from 'react-router-dom'
import { connect } from 'react-redux'
import { graphql, withApollo } from 'react-apollo'
import gql from 'graphql-tag'
import {
  Message
} from 'semantic-ui-react'
import PropTypes from 'prop-types'
import {
  lifecycle,
  compose,
  pure
} from 'recompose'
import {
  setupWeb3,
  hasMetamask,
  signMessage
} from './web3Helpers'
import AuthForm from './AuthForm'
import './login.css'

const propTypes = {
  user: PropTypes.shape({
    account: PropTypes.string,
    data: PropTypes.object,
    hasMetamask: PropTypes.bool,
    isLoading: PropTypes.bool.isRequired,
    error: PropTypes.bool.isRequired
  }).isRequired
}

export const Login = ({
  user,
  requestAuth,
  changeAccount,
  appLoaded,
  checkMetamask,
  authWithSAN,
  client
}) => {
  if (user.data.username && user.data.username.length > 0) {
    return <Redirect to={'/'} />
  }
  return (
    <div className='wrapper'>
      <div className='loginContainer'>
        {user.isLoading && !user.hasMetamask && <div>Loading</div>}
        {!user.hasMetamask && !user.isLoading &&
          <Message
            warning
            header={'We can\'t detect Metamask!'}
            list={[
              'We can auth you with Metamask account. It\'s secure and easy.'
            ]}
          />}
        {user.hasMetamask && !user.token &&
          <AuthForm
            account={user.account}
            handleAuth={() => requestAuth(user.account, authWithSAN, client)} />}
        {user.token &&
          <div>
            You are logged in! Redirecting...
            <Redirect to={'/'} />
          </div>
        }
      </div>
    </div>
  )
}

Login.propTypes = propTypes

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
    requestAuth: (account, authWithSAN, client) => {
      signMessage(account).then(({hashMessage, signature}) => {
        authWithSAN({variables: {
          signature: signature,
          address: account,
          addressHash: hashMessage}})
        .then(({ data }) => {
          const { token, user } = data.ethLogin
          dispatch({
            type: 'SUCCESS_LOGIN',
            token,
            username: user.username
          })
          // TODO:
          client.resetStore()
        }).catch((error) => {
          dispatch({
            type: 'FAILED_LOGIN',
            errorMessage: error
          })
          console.error(error)
        })
      }).catch(error => {
        // TODO: User denied, Account, etc.
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
    },
    appLoaded: () => {
      dispatch({
        type: 'APP_LOADING_SUCCESS'
      })
    }
  }
}

const requestAuthGQL = gql`
  mutation ethLogin($signature: String, $address: String, $addressHash: String) {
    ethLogin(
      signature: $signature,
      address: $address,
      addressHash: $addressHash) {
        token,
        user {
          username
        }
      }
}`

export default compose(
  connect(
    mapStateToProps,
    mapDispatchToProps
  ),
  withApollo,
  graphql(requestAuthGQL, {
    name: 'authWithSAN',
    options: { fetchPolicy: 'network-only' }
  }),
  lifecycle({
    componentDidMount () {
      this.props.checkMetamask(hasMetamask())
      setTimeout(() => {
        this.props.appLoaded()
      }, 1000)
      setupWeb3((error, account) => {
        if (!error && this.props.account !== account) {
          this.props.changeAccount(account)
        }
      })
    }
  }),
  pure
)(Login)
