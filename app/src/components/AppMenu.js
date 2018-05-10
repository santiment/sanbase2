import React from 'react'
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
  showIcons = false,
  showInsights = false,
  location = null
}) => (
  <div>
    <ul className={showIcons ? 'menu-list' : 'menu-list-top'} >
      {showInsights &&
      <li
        className={isPageFromLocation(location, 'insights') ? 'active' : ''}
        onClick={() => handleNavigation('insights')}>
        Insights
      </li>}
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
      <li
        className={isPageFromLocation(location, 'roadmap') ? 'active' : ''}
        onClick={() => handleNavigation('roadmap')}>
        Roadmap
      </li>
    </ul>
  </div>
)

export default AppMenu
