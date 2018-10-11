import Layout from '../components/Layout.js'
import TodoList from '../components/TodoList.js'
import fetch from 'isomorphic-unfetch'
import { WEBSITE_URL } from '../config'

const Index = (props) => {}

Index.getInitialProps = function({ res }) {
  if (res) {
    res.writeHead(301, { Location: '/cashflow' })
    res.end()
    res.finished = true
  } else {
    Router.replace('/cashflow')
  }
  return {}
}

export default Index
