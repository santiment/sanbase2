import React, { Fragment } from 'react'
import { Link } from 'react-router-dom'
import { Popup, Button, Icon } from 'semantic-ui-react'
import './AppMenu.css'

const isPageFromLocation = (location, pagename = '') => {
  if (location) {
    return pagename === location.pathname.split('/')[1]
  }
  return false
}

const AppMenu = ({
  handleNavigation,
  showIcons,
  isMobile,
  showInsights,
  location = null
}) => (
  <div>
    <ul className={showIcons ? 'menu-list' : 'menu-list-top'} >
      {showInsights &&
        <li
          className={isPageFromLocation(location, 'insights') ? 'active' : ''}
          onClick={() => handleNavigation('insights')}>
          Insights
        </li>
      }
      {isMobile
        ? <Fragment>
          <li
            className={isPageFromLocation(location, 'projects') ? 'active' : ''}
            onClick={() => handleNavigation('projects')}>
            ERC20 Projects
          </li>
          <li
            className={isPageFromLocation(location, 'currencies') ? 'active' : ''}
            onClick={() => handleNavigation('currencies')}>
            Currencies
          </li>
          <li
            className={isPageFromLocation(location, 'signals') ? 'active' : ''}
            onClick={() => handleNavigation('signals')}>
            Signals
          </li>
          <li
            className={isPageFromLocation(location, 'roadmap') ? 'active' : ''}
            onClick={() => handleNavigation('roadmap')}>
            Roadmap
          </li>
        </Fragment>
        : <Fragment>
          <Link
            className='app-menu__page-link'
            to={'/projects'}>
            Markets
          </Link>
          <Link
            className='app-menu__page-link'
            to={'/signals'}>
            Signals
          </Link>
          <Link
            className='app-menu__page-link'
            to={'/roadmap'}>
            Roadmap
          </Link>
        </Fragment>}
      {showInsights &&
      <Popup
        position='bottom left'
        basic
        wide
        trigger={
          <li>
            <Icon
              className='app-menu-creation-icon'
              fitted
              name='plus' />
          </li>
        } on='click'>
        <div className='app-menu-creation-list'>
          <Button
            basic
            color='green'
            onClick={() => handleNavigation('insights/new')}
          >
            Create new insight
          </Button>
          <Button
            basic
            onClick={() =>
              window.location.replace('https://santiment.typeform.com/to/EzKW7E')}
          >
            Request new token
          </Button>
        </div>
      </Popup>}
    </ul>
  </div>
)

export default AppMenu
