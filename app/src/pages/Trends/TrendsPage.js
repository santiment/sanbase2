import React from 'react'
import { withRouter } from 'react-router-dom'
import TrendsForm from '../../components/Trends/TrendsForm'
import TrendsExamples from '../../components/Trends/Examples/TrendsExamples'
import './TrendsPage.css'

const TrendsPage = ({ history }) => {
  return (
    <div className='TrendsPage'>
      <h1 className='TrendsPage__title'>Explore any crypto trend</h1>
      <TrendsForm history={history} />
      <TrendsExamples history={history} />
    </div>
  )
}

export default withRouter(TrendsPage)
