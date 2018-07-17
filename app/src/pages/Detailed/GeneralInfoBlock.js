import React from 'react'
import cx from 'classnames'
import { formatCryptoCurrency, formatNumber } from './../../utils/formatting'
import './GeneralInfoBlock.css'

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
      <div>{formatNumber(marketcapUsd, { currency: 'USD' })}</div>
    </div>
    <div className={`row-info ${!priceUsd && 'info-disabled'}`}>
      <div>Price</div>
      <div>{formatNumber(priceUsd, { currency: 'USD' })}</div>
    </div>
    <div className={`row-info ${!volumeUsd && 'info-disabled'}`}>
      <div>Volume</div>
      <div>{formatNumber(volumeUsd, { currency: 'USD' })}</div>
    </div>
    <div className={`row-info ${!marketcapUsd && 'info-disabled'}`}>
      <div>Circulating</div>
      <div>
        {formatCryptoCurrency(ticker, formatNumber(marketcapUsd / priceUsd))}
      </div>
    </div>
    <div
      className={cx({
        'row-info': true,
        'info-disabled': !isERC20
      })}
    >
      <div>Total supply</div>
      <div>
        {isERC20 ? formatCryptoCurrency(ticker, formatNumber(totalSupply)) : ''}
      </div>
    </div>
    <div className={`row-info ${!rank && 'info-disabled'}`}>
      <div>Rank</div>
      <div>{rank}</div>
    </div>
    <div className={`row-info ${!roiUsd && 'info-disabled'}`}>
      <div>ROI since ICO</div>
      <div>{roiUsd && parseFloat(roiUsd).toFixed(2)}</div>
    </div>
  </div>
)

export default GeneralInfoBlock
