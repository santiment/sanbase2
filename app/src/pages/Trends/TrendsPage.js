import React from 'react'
import { withRouter } from 'react-router-dom'
import TrendsForm from '../../components/Trends/TrendsForm'
import TrendsExamples from '../../components/Trends/Examples/TrendsExamples'

import './TrendsPage.css'

const TrendsPage = () => {
  return (
    <div className='TrendsPage'>
      <h1 className='TrendsPage__title'>Explore any crypto trend</h1>
      <TrendsForm />
      <TrendsExamples />
    </div>
  )
}

export default withRouter(TrendsPage)
