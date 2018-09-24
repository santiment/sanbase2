import React from 'react'
import HelpPopup from './../../components/HelpPopup/HelpPopup'
import './../../components/HelpPopup/HelpPopupProjectsContent.css'

const HelpPopupTrends = () => (
  <HelpPopup>
    <div className='HelpPopupProjectsContent'>
      <p>Enter a single word, or a phrase in these formats:</p>
      <ul
        style={{
          listStyleType: 'disc'
        }}
        className='HelpPopupProjectsContent__list'
      >
        <li className='HelpPopupProjectsContent__item'>
          "btc moon" will search for exact phrase
        </li>
        <li className='HelpPopupProjectsContent__item'>
          btc AND moon will search for btc and moon in the same message
        </li>
        <li className='HelpPopupProjectsContent__item'>
          btc OR moon will search for either btc or moon
        </li>
        <li className='HelpPopupProjectsContent__item'>
          btc moon is the same as btc OR moon
        </li>
      </ul>
    </div>
  </HelpPopup>
)

export default HelpPopupTrends
