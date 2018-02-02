import React from 'react'
import * as qs from 'query-string'
import { Redirect } from 'react-router-dom'
import { connect } from 'react-redux'
import { graphql, withApollo } from 'react-apollo'
import gql from 'graphql-tag'
import { Button, Icon } from 'semantic-ui-react'
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
} from '../../web3Helpers'
import metamaskIcon from '../../assets/metamask-icon-64.png'
import Panel from './../../components/Panel'
import './Login.css'

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
  location,
  client,
  isDesktop
}) => {
  if (location) {
    const qsData = qs.parse(location.search)
    if (qsData && qsData.redirect_to && user.token) {
      return <Redirect to={qsData.redirect_to} />
    }
  }
  if (user.data.hasOwnProperty('username') || user.token) {
    return <Redirect to='/' />
  }
  return (
    <div className='page login wrapper'>
      <Panel className='login-inner'>
        <h1>
          Welcome to Sanbase
        </h1>
        <p>
          By having a Sanbase account, you can see more data and insights about crypto projects.
          You can vote and comment on all your favorite insights and more.
        </p>
        <div className='login-actions'>
          <Button
            basic
            style={{
              display: 'flex',
              alignItems: 'center',
              paddingTop: '5px',
              paddingBottom: '5px'
            }}
          >
            <img
              src={metamaskIcon}
              alt='metamask logo'
              width={32}
              height={32} />
            Sign in with Metamask
          </Button>
          <Button
            basic
            className='sign-in-btn'
          >
            <Icon size='large' name='mail outline' />
            <span>Sign in with email</span>
          </Button>
        </div>
      </Panel>
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
  }),
  pure
)(Login)
