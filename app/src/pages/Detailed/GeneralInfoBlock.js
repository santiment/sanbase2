import React from 'react'
import { formatNumber } from '../../utils/formatting'
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
    <div className={`row-info ${!marketcapUsd && 'info-disabled'}`}>
      <div>
        Market Cap
      </div>
      <div>
        {formatNumber(marketcapUsd, 'USD')}
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
    <div className={`row-info ${!volumeUsd && 'info-disabled'}`}>
      <div>
        Volume
      </div>
      <div>
        {formatNumber(volumeUsd, 'USD')}
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
