import React from 'react'

import './HelpPopupProjectsContent.css'

const HelpPopupProjectsContent = () => {
  return (
    <div className='HelpPopupProjectsContent'>
      <h3 className='HelpPopupProjectsContent__title'>
        This overview can be used to:
      </h3>
      <ol className='HelpPopupProjectsContent__list'>
        <li className='HelpPopupProjectsContent__item'>
          <h4>1. Spot potentially undervalued projects.</h4>
          <p>
            These projects generally have more in "crypto cash" balance than their market capitalization. Look for a value more than 1 in the CAP/BALANCE column.
          </p>
        </li>
        <li className='HelpPopupProjectsContent__item HelpPopupProjectsContent__item_inline'>
          <h4>2. See if, and how much, </h4>
          <p>
            a project is "dumping" its collected ETH funds. Look for this in the TRANSACTIONS column.
          </p>
        </li>
        <li className='HelpPopupProjectsContent__item HelpPopupProjectsContent__item_inline'>
          <h4>3. See how active a project's team is </h4>
          <p>
            in building their product. Look for this in the DEV ACTIVITY column which shows a summary of Github activity.
          </p>
        </li>
      </ol>
      <h4 className='HelpPopupProjectsContent__subtitle'>
        Are you following a project but don't see it here?
      </h4>
      <p>
        That means their wallet information isn't available. Why not talk to their project leadership and ask them to disclose it? Financial transparence is important and should be available to everyone in the cryptospace.
      </p>
      <p>
        <a
          href='https://docs.google.com/forms/d/e/1FAIpQLSeFuCxjJjId98u1Bp3qpXCq2A9YAQ02OEdhOgiM9Hr-rMDxhQ/viewform'
          className='HelpPopupProjectsContent__link'
        >
          Once you have the data - submit it here.{' '}
        </a>
        Your project will then be in the overview!
      </p>
    </div>
  )
}

export default HelpPopupProjectsContent
