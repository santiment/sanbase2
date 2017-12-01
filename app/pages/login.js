import withRedux from 'next-redux-wrapper'
import Login from 'containers/login'
import initStore from 'store.js'

export default withRedux(initStore)(Login)
