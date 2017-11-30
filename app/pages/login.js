import withRedux from 'next-redux-wrapper'
import LoginContainer from 'containers/login'
import initStore from 'store.js'

export default withRedux(initStore)(LoginContainer)
