import React from 'react'
import { storiesOf } from '@storybook/react'
import PanelBlock from './../src/components/PanelBlock'
import GeneralInfoBlock from './../src/components/GeneralInfoBlock'
import FinancialsBlock from './../src/components/FinancialsBlock'

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

const project2 = {
  name: 'Santiment Network Token',
  id: '23',
  ticker: 'SAN',
  fundsRaisedIcos: [],
  ethBalance: '33998.28563720823'
}

const ethPrice = 972.19
const wallets = [{
  tx_out: '0.00',
  last_outgoing: '2017-12-24T12:49:20',
  balance: '33998.29',
  address: '0x6dD5A9F47cfbC44C04a0a4452F0bA792ebfBcC9a'
}]

storiesOf('Project Detailted Page', module)
  .add('General Info Block', () => (
    <PanelBlock
      isUnauthorized={false}
      isLoading={false}
      title='General Info'>
      <GeneralInfoBlock
        btcBalance={null}
        facebookLink={null}
        fundsRaisedIcos={[]}
        githubLink={null}
        id={project.id}
        marketCapUsd={null}
        name={project.name}
        projectTransprency={false}
        projectTransparencyDescription={null}
        projectTransparencyStatus={null}
        redditLink={null}
        slackLink={null}
        ticker={project.ticker}
        tokenAddress={null}
        twitterLink={null}
        volume={'1432780'}
        websiteLink={'https://aragon.one/'}
        whitepaperLink={null} />
    </PanelBlock>
  ))
  .add('Financials Info Block', () => (
    <PanelBlock
      isUnauthorized={false}
      isLoading={false}
      title='Financial Info'>
      <FinancialsBlock
        ethPrice={ethPrice}
        wallets={wallets}
        {...project} />
    </PanelBlock>
  ))
  .add('Financials Info Block Loading', () => (
    <PanelBlock
      isLoading
      isUnauthorized={false}
      title='Financial Info'>
      <FinancialsBlock
        ethPrice={ethPrice}
        wallets={wallets}
        {...project} />
    </PanelBlock>
  ))
  .add('Financials Info Block isUnauthorized', () => (
    <PanelBlock
      isUnauthorized
      isLoading={false}
      title='Financial Info'>
      <FinancialsBlock
        ethPrice={ethPrice}
        wallets={wallets}
        {...project} />
    </PanelBlock>
  ))
  .add('Financials Info Block without Collected data', () => (
    <PanelBlock
      isUnauthorized={false}
      isLoading={false}
      title='Financial Info'>
      <FinancialsBlock
        ethPrice={ethPrice}
        wallets={wallets}
        {...project2} />
    </PanelBlock>
  ))
