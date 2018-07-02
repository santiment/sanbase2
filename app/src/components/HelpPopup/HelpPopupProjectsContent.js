import React from 'react'

import './HelpPopupProjectsContent.css'

const HelpPopupProjectsContent = () => {
  return (
    <div className='HelpPopupProjectsContent'>
      <p>The "Markets" section includes lists of tokens you can use to:</p>
      <ol className='HelpPopupProjectsContent__list'>
        <li className='HelpPopupProjectsContent__item'>
          <h4>1. Spot increase or decrease in token usage.</h4>
          <p>
            Look at the DAILY ACTIVE ADDRESSES column to see how many unique addresses participated in transactions for that token for the last 30 days. Sudden increases in activity can sometimes preceed sharp price movements.
          </p>
        </li>
        <li className='HelpPopupProjectsContent__item'>
          <h4>2. See if, and how much, a project is "dumping" its collected ETH funds.</h4>
          <p>
            Look for this figure in the ETH SPENT column. Activity here could effect the price of ETH and, by extention, related tokens.
          </p>
        </li>
        <li className='HelpPopupProjectsContent__item'>
          <h4>3. See how active a project's team is in building their product.</h4>
          <p>
            Look for this metric in the DEV ACTIVITY column, which shows a summary of Github activity.
          </p>
        </li>
        <li className='HelpPopupProjectsContent__item HelpPopupProjectsContent__item_inline'>
          <h4>4. Compare tokens.</h4>
          <p>
            Click the column headers to sort by the various metrics.
          </p>
        </li>
        <li className='HelpPopupProjectsContent__item HelpPopupProjectsContent__item_inline'>
          <h4>5. Get details, including price charts, for each token.</h4>
          <p>
            Click the token name to drill down to a detail page.
          </p>
        </li>
      </ol>
    </div>
  )
}

export default HelpPopupProjectsContent
