import React from 'react'
import { Popup } from 'semantic-ui-react'
import { style } from '..//HelpPopup/HelpPopup'
import './TrendsTitle.css'

const TrendsPageTitleWithPopup = () => (
  <Popup
    trigger={<h1 className='TrendsTitle'>Social Trends</h1>}
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
        <p>
          Results include mentions from 20+ Telegram channels, numerous
          Subreddits and Discord channels, plus mentions on BitcoinTalk and
          TradingView forums.{' '}
        </p>
      </div>
    }
  />
)

export default TrendsPageTitleWithPopup
