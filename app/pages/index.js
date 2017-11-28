import Router from 'next/router'

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
