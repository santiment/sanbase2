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
  marketcap,
  rank,
  priceUsd,
  totalSupply,
  volume,
  ticker,
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
    <div className={`row-info ${!marketcap && 'info-disabled'}`}>
      <div>
        Market Cap
      </div>
      <div>
        {formatNumber(marketcap, 'USD')}
      </div>
    </div>
    <div className={`row-info ${!priceUsd && 'info-disabled'}`}>
      <div>
        Price
      </div>
      <div>
        {formatNumber(priceUsd, 'USD')}
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
    <div className={`row-info ${!marketcap && 'info-disabled'}`}>
      <div>
        Circulating
      </div>
      <div>
        {ticker}&nbsp;
        {formatNumber(marketcap / priceUsd)}
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
        {roiUsd}
      </div>
    </div>
  </div>
)

export default GeneralInfoBlock
