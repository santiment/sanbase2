import Layout from '../components/Layout.js'
import TodoList from '../components/TodoList.js'
import fetch from 'isomorphic-unfetch'

const Index = (props) => {}

Index.getInitialProps = ({res}) => {
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
