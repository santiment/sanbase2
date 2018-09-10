import React from 'react'
import TrendsForm from '../../components/Trends/TrendsForm'
import TrendsExamples from '../../components/Trends/Examples/TrendsExamples'
import './TrendsPage.css'

const TrendsPage = () => (
  <div className='TrendsPage page'>
    <h1 className='TrendsPage__title'>Explore any crypto trend</h1>
    <TrendsForm />
    <TrendsExamples />
  </div>
)

export default TrendsPage
