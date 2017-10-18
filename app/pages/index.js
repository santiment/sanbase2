import Layout from '../components/Layout.js'
import TodoList from '../components/TodoList.js'
import fetch from 'isomorphic-unfetch'
import { WEBSITE_URL } from '../config'

const Index = (props) => (
  <Layout>
    <p>Your current shopping list:</p>
    <TodoList items={props.items}/>
  </Layout>
)

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
