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
  roiUsd
}) => (
  <div>
    <p className='social-icons'>
      <a href={websiteLink || ''}>
        <i className={`fa fa-globe ${!websiteLink && 'fa-disabled'}`} />
      </a>
      <a href={slackLink || ''}>
        <i className={`fa fa-slack ${!slackLink && 'fa-disabled'}`} />
      </a>
      <a href={twitterLink || ''}>
        <i className={`fa fa-twitter ${!twitterLink && 'fa-disabled'}`} />
      </a>
      <a href={mediumLink || ''}>
        <i className={`fa fa-medium ${!mediumLink && 'fa-disabled'}`} />
      </a>
      <a href={githubLink || ''}>
        <i className={`fa fa-github ${!githubLink && 'fa-disabled'}`} />
      </a>
      <a
        className={`${!whitepaperLink && 'fa-disabled'}`}
        href={whitepaperLink || ''}>
        Whitepaper
      </a>
    </p>
    <hr />
    <div className={`row-info ${latestCoinmarketcapData && !latestCoinmarketcapData.marketCapUsd && 'info-disabled'}`}>
      <div>
        Market Cap
      </div>
      <div>
        {latestCoinmarketcapData && formatNumber(latestCoinmarketcapData.marketCapUsd, 'USD')}
      </div>
    </div>
    <div className={`row-info ${latestCoinmarketcapData && !latestCoinmarketcapData.priceUsd && 'info-disabled'}`}>
      <div>
        Price
      </div>
      <div>
        {latestCoinmarketcapData && formatNumber(latestCoinmarketcapData.priceUsd, 'USD')}
      </div>
    </div>
    <div className={`row-info ${!volume && 'info-disabled'}`}>
      <div>
        Volume
      </div>
      <div>
        {formatNumber(volume, 'USD')}
        <HiddenElements>
          <span className='diff down'>
            <i className='fa fa-caret-down' />
            &nbsp; 8.87%
          </span>
        </HiddenElements>
      </div>
    </div>
    <div className={`row-info ${latestCoinmarketcapData && !latestCoinmarketcapData.marketCapUsd && 'info-disabled'}`}>
      <div>
        Circulating
      </div>
      <div>
        {latestCoinmarketcapData && latestCoinmarketcapData.symbol}&nbsp;
        {latestCoinmarketcapData && formatNumber(latestCoinmarketcapData.marketCapUsd / latestCoinmarketcapData.priceUsd)}
      </div>
    </div>
    <div className={`row-info ${latestCoinmarketcapData && !latestCoinmarketcapData.totalSupply && 'info-disabled'}`}>
      <div>
        Total supply
      </div>
      <div>
        {latestCoinmarketcapData && latestCoinmarketcapData.symbol}&nbsp;
        {latestCoinmarketcapData && formatNumber(latestCoinmarketcapData.totalSupply)}
      </div>
    </div>
    <div className={`row-info ${latestCoinmarketcapData && !latestCoinmarketcapData.rank && 'info-disabled'}`}>
      <div>
        Rank
      </div>
      <div>
        {latestCoinmarketcapData && latestCoinmarketcapData.rank}
      </div>
    </div>
    <div className={`row-info ${!roiUsd && 'info-disabled'}`}>
      <div>
        ROI since ICO
      </div>
      <div>
        {roiUsd}
      </div>
    </div>
  </div>
)

GeneralInfoBlock.propTypes = propTypes

export default GeneralInfoBlock
