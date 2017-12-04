import React from 'react'
import { connect } from 'react-redux'
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
  checkMetamask
}) => (
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
      {user.hasMetamask &&
        <AuthForm
          account={user.account}
          handleAuth={() => requestAuth(user.account)} />}
    </div>
  </div>
)

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
    requestAuth: account => {
      signMessage(account).then(res => {
        console.log(res)
      }).catch(error => {
        // TODO: User denied, Account, etc.
        console.log(error)
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

export default compose(
  connect(
    mapStateToProps,
    mapDispatchToProps
  ),
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
