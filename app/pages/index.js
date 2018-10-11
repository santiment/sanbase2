import Layout from '../components/Layout.js'
import TodoList from '../components/TodoList.js'
import fetch from 'isomorphic-unfetch'

export default class extends React.Component {
  static async getInitialProps ({ res }) {
    return redirect_to(res, '/cashflow')
  }
}
