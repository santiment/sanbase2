import React from 'react'
import { withRouter } from 'react-router-dom'
import TrendsForm from '../../components/Trends/TrendsForm'

const TrendsPage = ({ history }) => {
  return (
    <div>
      <TrendsForm history={history} />
    </div>
  )
}

export default withRouter(TrendsPage)
