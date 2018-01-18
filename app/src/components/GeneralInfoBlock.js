import React from 'react'
import { formatNumber } from '../utils/formatting'
import { HiddenElements } from '../pages/Detailed'
import './GeneralInfoBlock.css'

const GeneralInfoBlock = ({
  websiteLink,
  slackLink,
  twitterLink,
  githubLink,
  mediumLink,
  whitepaperLink,
  marketcapUsd,
  rank,
  priceUsd,
  totalSupply,
  volumeUsd,
  ticker,
  roiUsd
}) => (
  <div>
    <p className='social-icons'>
      <a href='#'>
        <i className='fa fa-globe' />
      </a>
      <a href='#'>
        <i className='fa fa-slack' />
      </a>
      <a href='#'>
        <i className='fa fa-twitter' />
      </a>
      <a href={mediumLink || ''}>
        <i className={`fa fa-medium ${!mediumLink && 'fa-disabled'}`} />
      </a>
      <a href='#'>
        <i className='fa fa-github' />
      </a>
    </p>
    <hr />
    <div className={`row-info ${!latestCoinmarketcapData.marketCapUsd && 'info-disabled'}`}>
      <div>
        Market Cap
      </div>
      <div>
        ${info.market_cap_usd}
      </div>
    </div>
    <div className={`row-info ${!volumeUsd && 'info-disabled'}`}>
      <div>
        Volume
      </div>
      <div>
        {formatNumber(volumeUsd, 'USD')}
        <HiddenElements>
          <span className='diff down'>
            <i className='fa fa-caret-down' />
            &nbsp; 8.87%
          </span>
        </HiddenElements>
      </div>
    </div>
    <div className={`row-info ${!marketcapUsd && 'info-disabled'}`}>
      <div>
        Circulating
      </div>
      <div>
        {ticker}&nbsp;
        {formatNumber(marketcapUsd / priceUsd)}
      </div>
    </div>
    <div className={`row-info ${!totalSupply && 'info-disabled'}`}>
      <div>
        Total supply
      </div>
      <div>
        {ticker}&nbsp;
        {formatNumber(totalSupply)}
      </div>
    </div>
    <div className={`row-info ${!rank && 'info-disabled'}`}>
      <div>
        Rank
      </div>
      <div>
        {rank}
      </div>
    </div>
    <div className={`row-info ${!roiUsd && 'info-disabled'}`}>
      <div>
        ROI since ICO
      </div>
      <div>
        {roiUsd && parseFloat(roiUsd).toFixed(2)}
      </div>
    </div>
  </div>
)

export default GeneralInfoBlock
