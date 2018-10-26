import { graphql } from 'react-apollo'
import { HistoryPriceGQL } from '../Detailed/DetailedGQL'

const GetHistoryPrice = ({ render, children, data }) => {
  const show = render || children
  return show(data)
}

export default graphql(HistoryPriceGQL, {
  options: ({ slug, interval, from }) => {
    return {
      errorPolicy: 'all',
      variables: {
        from,
        interval,
        slug
      }
    }
  }
})(GetHistoryPrice)
