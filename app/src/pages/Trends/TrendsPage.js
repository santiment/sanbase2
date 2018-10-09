import React from 'react'
import { Popup } from 'semantic-ui-react'
import TrendsExamples from '../../components/Trends/Examples/TrendsExamples'
import TrendsExamplesItemTopic from '../../components/Trends/Examples/TrendsExamplesItemTopic'
import { style } from './../../components/HelpPopup/HelpPopup'
import './TrendsPage.scss'

const TrendsPageTitleWithPopup = () => (
  <Popup
    trigger={<h1>Social Trends</h1>}
    position='bottom center'
    on='hover'
    style={style}
    content={
      <div>
        <p>
          Our Social Trends search is unique in the industry, based on channels,
          sites and forums.
        </p>
        <p>
          We focus only on channels where 90% of the discussions about crypto,
          including "insider" sites not open to public Google search.
        </p>
        <h4>Combined results include:</h4>
        <ul>
          <li>20 Telegram channels</li>
          <li>Subreddits</li>
          <li>Discord Channels</li>
          <li>BitcoinTalk</li>
          <li>Other chats/forums</li>
        </ul>
      </div>
    }
  />
)

const TrendsPage = () => (
  <div className='TrendsPage page'>
    <div className='TrendsPage__header'>
      <div>
        <TrendsPageTitleWithPopup />
      </div>
      <div>
        <p>
          See how often a word or phrase is used in crypto social media, plotted
          against BTC or ETH price
        </p>
      </div>
    </div>
    <TrendsExamplesItemTopic />
    <TrendsExamples />
  </div>
)

export default TrendsPage
