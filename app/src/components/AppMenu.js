import React, { Fragment } from 'react'
import { Popup, Button, Icon } from 'semantic-ui-react'
import './AppMenu.css'

const AppMenu = ({handleNavigation, showIcons = false, showInsights = false}) => (
  <div style={{
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'center'
  }}>
    {showInsights &&
    <ul className={showIcons ? 'menu-list user-generated' : 'menu-list-top user-generated'} >
      <li onClick={() => handleNavigation('insights')}>
        {showIcons && <i className='fa fa-newspaper-o' />}
        Insights
      </li>
    </ul>}
    <ul className={showIcons ? 'menu-list' : 'menu-list-top'} >
      <li onClick={() => handleNavigation('projects')}>
        {showIcons && <Icon name='list 2x' />}
        ERC20 Projects
      </li>
      <li onClick={() => handleNavigation('currencies')}>
        {showIcons && <Icon name='list 2x' />}
        Currencies
      </li>
      <li onClick={() => handleNavigation('signals')}>
        {showIcons && <Icon name='th 2x' />}
        Signals
      </li>
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
      </Popup>
    </ul>
  </div>
)

export default AppMenu
