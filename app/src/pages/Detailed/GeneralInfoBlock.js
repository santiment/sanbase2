import React from 'react'
import cx from 'classnames'
import { formatCryptoCurrency, formatNumber } from './../../utils/formatting'
import './GeneralInfoBlock.css'

const DATA_IS_EMPTY = 'No data'

const GeneralInfoBlock = ({
  websiteLink,
  slackLink,
  twitterLink,
  githubLink,
  blogLink,
  whitepaperLink,
  marketcapUsd,
  rank,
  priceUsd,
  totalSupply,
  volumeUsd,
  ticker,
  roiUsd,
  isERC20
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
      <a href={blogLink || ''}>
        <i className={`fa fa-medium ${!blogLink && 'fa-disabled'}`} />
      </a>
      <a href={githubLink || ''}>
        <i className={`fa fa-github ${!githubLink && 'fa-disabled'}`} />
      </a>
      <a
        className={`${!whitepaperLink && 'fa-disabled'}`}
        href={whitepaperLink || ''}
      >
        Whitepaper
      </a>
    </p>
    <hr />
    <div className={`row-info ${!marketcapUsd && 'info-disabled'}`}>
      <div>Market Cap</div>
      <div>
        {marketcapUsd && formatNumber(marketcapUsd, { currency: 'USD' })}
      </div>
    </div>
    <div className={`row-info ${!priceUsd && 'info-disabled'}`}>
      <div>Price</div>
      <div>{priceUsd && formatNumber(priceUsd, { currency: 'USD' })}</div>
    </div>
    <div className={`row-info ${!volumeUsd && 'info-disabled'}`}>
      <div>Volume</div>
      <div>{volumeUsd && formatNumber(volumeUsd, { currency: 'USD' })}</div>
    </div>
    <div className={`row-info ${!marketcapUsd && 'info-disabled'}`}>
      <div>Circulating</div>
      <div>
        {marketcapUsd && priceUsd
          ? formatCryptoCurrency(ticker, formatNumber(marketcapUsd / priceUsd))
          : DATA_IS_EMPTY}
      </div>
    </div>
    <div
      className={cx({
        'row-info': true,
        'info-disabled': !totalSupply
      })}
    >
      <div>Total supply</div>
      <div>
        {totalSupply
          ? formatCryptoCurrency(ticker, formatNumber(totalSupply))
          : DATA_IS_EMPTY}
      </div>
    </div>
    <div className={`row-info ${!rank && 'info-disabled'}`}>
      <div>Rank</div>
      <div>{rank || DATA_IS_EMPTY}</div>
    </div>
    <div className={`row-info ${!roiUsd && 'info-disabled'}`}>
      <div>ROI since ICO</div>
      <div>{roiUsd ? parseFloat(roiUsd).toFixed(2) : DATA_IS_EMPTY}</div>
    </div>
  </div>
)

export default GeneralInfoBlock
