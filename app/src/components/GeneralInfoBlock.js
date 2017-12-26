import React from 'react'
import PropTypes from 'prop-types'
import { formatNumber } from '../utils/formatting'
import { HiddenElements } from '../pages/Detailed'
import './GeneralInfoBlock.css'

const propTypes = {
  websiteLink: PropTypes.string,
  slackLink: PropTypes.string,
  twitterLink: PropTypes.string,
  githubLink: PropTypes.string,
  mediumLink: PropTypes.string,
  whitepaperLink: PropTypes.string,
  latestCoinmarketcapData: PropTypes.object
}

const GeneralInfoBlock = ({
  websiteLink,
  slackLink,
  twitterLink,
  githubLink,
  mediumLink,
  whitepaperLink,
  latestCoinmarketcapData,
  marketCapUsd,
  rank,
  volume,
  circulating,
  totalSupply,
  roi
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
    <div className={`row-info ${!volume && 'info-disabled'}`}>
      <div>
        Volume
      </div>
      <div>
        ${volume}
        <HiddenElements>
          <span className='diff down'>
            <i className='fa fa-caret-down' />
            &nbsp; 8.87%
          </span>
        </HiddenElements>
      </div>
    </div>
    <div className={`row-info ${!circulating && 'info-disabled'}`}>
      <div>
        Circulating
      </div>
      <div>
        ${circulating}
      </div>
    </div>
    <div className={`row-info ${!totalSupply && 'info-disabled'}`}>
      <div>
        Total supply
      </div>
      <div>
        {totalSupply}
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
    <div className={`row-info ${!roi && 'info-disabled'}`}>
      <div>
        ROI since ICO
      </div>
      <div>
        {roi}
      </div>
    </div>
  </div>
)

GeneralInfoBlock.propTypes = propTypes

export default GeneralInfoBlock
