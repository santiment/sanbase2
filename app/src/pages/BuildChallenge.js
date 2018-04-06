import React from 'react'
import { Button } from 'semantic-ui-react'
import './BuildChallenge.css'

const BuildChallenge = () => {
  return (
    <div className='page build-challenge-page'>
      <h2>Santiment Build Challenge</h2>
      <p className='r--medium-lineHeight-tight'>
        The Santiment Build Challenge is an ongoing program to reward
        <br />
        innovation and development in the Santiment community and ecosystem.
      </p>
      <hr />
      <h2>Why?</h2>
      <p>Santiment has a lot of great data about Blockchain world. And we collect this data in realtime.</p>
      <p>We have great tools for developers and data for traders and crypto guru</p>
      <ul>
        <li>> 1,500 Coins and Blockchain Projects</li>
        <li>ETH spent per project, token burn rate and more...</li>
        <li>Great GraphQL API for manipulations with data</li>
      </ul>
      <hr />
      <div className='cta-block'>
        <div className='cta-block-button'>
          <Button basic color='green' content='Submit' />
          <div>#SantimentChallenge</div>
        </div>
      </div>
      <hr />
      <div>
        <h1>CATEGORIES</h1>
        <ul>
          <li>Portfolio Apps</li>
          <li>Any apps based on Santiment Signals/Data API</li>
          <li>Harvest new blockchain or exchanges data</li>
          <li>Analyze Santiment Data</li>
          <li>Insights around Crypto trades</li>
        </ul>
      </div>
    </div>
  )
}

export default BuildChallenge
