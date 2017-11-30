import { connect } from 'react-redux'
import {
  Form,
  Message,
  Button
} from 'semantic-ui-react'
import PropTypes from 'prop-types'
import {
  lifecycle,
  compose,
  pure
} from 'recompose'
import MainHead from 'components/main-head'
import { setupWeb3 } from 'web3Helpers'

const propTypes = {
  account: PropTypes.string,
  data: PropTypes.object,
  isLoading: PropTypes.bool.isRequired,
  error: PropTypes.bool.isRequired
}

const Login = ({account, isLoading, requestAuth, changeAccount, appLoaded}) => {
  return (
    <div>
      <MainHead />
      <div className='wrapper'>
        <div className='loginContainer'>
          <Form warning>
            {isLoading && <div>Loading</div>}
            {account && !isLoading &&
              <div>
                <Message
                  header='We detect you have Metamask!'
                  list={[
                    'We can auth you with Metamask account. It\'s secure and easy.',
                    `Your selected wallet public key is ${account}`
                  ]}
                />
                <Button
                  color='green'
                  onClick={() => requestAuth(account)}
                >Sign in with Metamask</Button>
              </div>}
            {!account && !isLoading &&
              <Message
                warning
                header={'We can\'t detect Metamask!'}
                list={[
                  'We can auth you with Metamask account. It\'s secure and easy.'
                ]}
              />}
          </Form>
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
          max-width: 50%;
          border-radius: 2px;
          box-shadow: 0 1.5px 0 0 rgba(0,0,0,0.1);
        }
      `}</style>
    </div>
  )
}

Login.propTypes = propTypes

const mapStateToProps = ({user}) => {
  return (
    user
  )
}

const mapDispatchToProps = dispatch => {
  return {
    requestAuth: account => {
      dispatch({
        type: 'REQUEST_AUTH_BY_SAN_TOKEN',
        account
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
      setupWeb3((error, account) => {
        if (!error && this.props.account !== account) {
          this.props.changeAccount(account)
        }
      })
      this.props.appLoaded()
    }
  }),
  pure
)(Login)
