import React from 'react'
import { storiesOf } from '@storybook/react'
import ProjectCard from './../src/pages/Projects/ProjectCard'

const project = {
  name: 'Santiment Network Token',
  id: '23',
  ticker: 'SAN',
  fundsRaisedIcos: [
    {
      currencyCode: 'BTC',
      amount: '4575.378211063582'
    }
  ],
  ethBalance: '33998.28563720823'
}

const ethPrice = 972.19
const wallets = [{
  tx_out: '0.00',
  last_outgoing: '2017-12-24T12:49:20',
  balance: '33998.29',
  address: '0x6dD5A9F47cfbC44C04a0a4452F0bA792ebfBcC9a'
}]

storiesOf('Cashflow page', module)
  .add('Project card', () => (
    <div style={{padding: 20}}>
      <ProjectCard />
    </div>
  ))
  .add('Project card list', () => (
    <div style={{padding: 20}}>
      <ProjectCard />
      <ProjectCard />
      <ProjectCard />
    </div>
  ))
