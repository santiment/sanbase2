import React, { Fragment } from 'react'
import { Link } from 'react-router-dom'
import TrendsForm from './TrendsForm'
import styles from './TrendsSearch.module.scss'
// import HelpPopupTrends from './../../../pages/Trends/HelpPopupTrends'
// import './TrendsExamplesItemTopic.css'
// <HelpPopupTrends className='TrendsExamplesItemTopic__help' />

const TrendsExampleLink = ({ keyword }) => (
  <Link to={`/trends/explore/${keyword}`}>
    &nbsp;
    {keyword}
  </Link>
)

const TrendsSearch = ({ topic, fontSize = '1em' }) => (
  <div className={styles.TrendsSearch} style={{ fontSize }}>
    <TrendsForm defaultTopic={topic} />
    <div className={styles.examples}>
      <span>Try to select</span>
      {['stablecoin', 'ICO', '(XRP OR Ripple OR XLM OR ETH) AND top'].map(
        (keyword, index, arr) => (
          <Fragment key={keyword}>
            <TrendsExampleLink keyword={keyword} />
            {index !== arr.length - 1 && ','}
          </Fragment>
        )
      )}
    </div>
  </div>
)

export default TrendsSearch
// <TrendsExampleLink keyword={keyword} key={keyword} />
