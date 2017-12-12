import React from 'react'
import { Tab, Tabs, TabList, TabPanel } from 'react-tabs'
import ProjectIcon from './../components/ProjectIcon'
import PanelBlock from './../components/PanelBlock'
import './Detailed.css'

const Detailed = () => (
  <div className='page detailed'>
    <div className='detailed-head'>
      <div className='detailed-name'>
        <h1><ProjectIcon name='aragon' size='28' /> Aragon (ANT)</h1>
        <p>Manage entire organisations using the blockchain.</p>
      </div>
      <div className='detailed-buttons'>
        <a href='#' className='add-to-dashboard'>
          <i className='fa fa-plus' />
          &nbsp; Add to Dashboard
        </a>
      </div>
    </div>
    <div className='panel'>
      <Tabs className='main-chart'>
        <TabList className='nav'>
          <Tab className='nav-item' selectedClassName='active'>
            <a className='nav-link' href='#'>
              $2.29 USD &nbsp;
              <span className='diff down'>
                <i className='fa fa-caret-down' />
                  &nbsp; 8.87%
              </span>
            </a>
          </Tab>
          <Tab className='nav-item' selectedClassName='active'>
            <a className='nav-link' href='#'>
              2.29 BTC &nbsp;
              <span className='diff up'>
                <i className='fa fa-caret-up' />
                  &nbsp; 8.87%
              </span>
            </a>
          </Tab>
        </TabList>
        <TabPanel>
          1
        </TabPanel>
        <TabPanel>
          2
        </TabPanel>
      </Tabs>
    </div>
    <div className='panel'>
      <Tabs className='activity-panel'>
        <TabList className='nav'>
          <Tab className='nav-item' selectedClassName='active'>
            <a className='nav-link' href='#'>
              Social Mentions
            </a>
          </Tab>
          <Tab className='nav-item' selectedClassName='active'>
            <a className='nav-link' href='#'>
              Social Activity over Time
            </a>
          </Tab>
          <Tab className='nav-item' selectedClassName='active'>
            <a className='nav-link' href='#'>
              Sentiment/Intensity
            </a>
          </Tab>
          <Tab className='nav-item' selectedClassName='active'>
            <a className='nav-link' href='#'>
              Github Activity
            </a>
          </Tab>
          <Tab className='nav-item' selectedClassName='active'>
            <a className='nav-link' href='#'>
              SAN Community
            </a>
          </Tab>
        </TabList>
        <TabPanel>
          Social Mentions
        </TabPanel>
        <TabPanel>
          Social Activity over Time
        </TabPanel>
        <TabPanel>
          Sentiment/Intensity
        </TabPanel>
        <TabPanel>
          Github Activity
        </TabPanel>
        <TabPanel>
          SAN Community
        </TabPanel>
      </Tabs>
    </div>
    <PanelBlock title='Blockchain Analytics' />
    <div className='row analysis'>
      <PanelBlock title='Signals/Volatility' />
      <PanelBlock title='Expert Analyses' />
      <PanelBlock title='News/Press' />
    </div>
    <div className='row information'>
      <PanelBlock title='General Info' />
      <PanelBlock title='Financials' />
    </div>
  </div>
)

export default Detailed
