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
      <a href='#'>
        <i className='fa fa-globe' />
      </a>
      <a href='#'>
        <i className='fa fa-slack' />
      </a>
      <a href='#'>
        <i className='fa fa-twitter' />
      </a>
      <a href={blogLink || ''}>
        <i className={`fa fa-medium ${!blogLink && 'fa-disabled'}`} />
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
      <div>Volume</div>
      <div>{formatNumber(volumeUsd, { currency: 'USD' })}</div>
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
