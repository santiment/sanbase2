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
import { setupWeb3, hasMetamask } from 'web3Helpers'
import Head from 'components/head'
import AuthForm from 'components/AuthForm'

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
  <div>
    <Head />
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
            handleAuth={() => this.props.requestAuth(user.account)} />}
      </div>
    </div>
    <style jsx>{`
      .wrapper {
        display: flex;
        justify-content: center;
        align-items: center;
        height: 100vh;
      }
      .loginContainer {
        padding: 1em;
        background: white;
        max-width: 70%;
        border-radius: 2px;
        box-shadow: 0 1.5px 0 0 rgba(0,0,0,0.1);
      }
    `}</style>
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
      // TODO: request auth with san token
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
