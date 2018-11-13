import React from 'react'
import HelpPopup from './../../components/HelpPopup/HelpPopup'
import './../../components/HelpPopup/HelpPopupProjectsContent.css'

const HelpPopupTrends = ({ className }) => (
  <HelpPopup className={className}>
    <div className='HelpPopupProjectsContent'>
      <p>Enter a single word, or a phrase in these formats:</p>
      <ul
        style={{
          listStyleType: 'disc',
          marginLeft: '17px'
        }}
        className='HelpPopupProjectsContent__list'
      >
        <li className='HelpPopupProjectsContent__item'>
          <code>btc moon</code> will search for the exact phrase
        </li>
        <li className='HelpPopupProjectsContent__item'>
          <code>btc AND moon</code> will search for btc and moon in the same
          message
        </li>
        <li className='HelpPopupProjectsContent__item'>
          <code>btc OR moon</code> will search for either btc or moon
        </li>
        <li className='HelpPopupProjectsContent__item'>
          You can use a more complex query:{' '}
          <pre>
            <code>(btc OR moon) AND something</code>
          </pre>
        </li>
      </ul>
    </div>
  </HelpPopup>
)

export default HelpPopupTrends
