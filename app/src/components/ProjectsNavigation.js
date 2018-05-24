import React from 'react'
import { NavLink as Link } from 'react-router-dom'
import {
  Button,
  Checkbox,
  Popup
} from 'semantic-ui-react'
import './ProjectsNavigation.css'

const HiddenElements = () => ''

const ProjectsNavigation = ({
  path,
  categories,
  handleSetCategory,
  allMarketSegments,
  user
}) => {
  return (
    <div className='projects-navigation'>
      <div className='projects-navigation-list'>
        <Link
          activeClassName='projects-navigation-list__page-link--active'
          className='projects-navigation-list__page-link'
          to={'/projects'}>
          ERC20 Projects
        </Link>
        <Link
          activeClassName='projects-navigation-list__page-link--active'
          className='projects-navigation-list__page-link'
          to={'/currencies'}>
          Currencies
        </Link>
        {user.token &&
          <Link
            activeClassName='projects-navigation-list__page-link--active'
            className='projects-navigation-list__page-link'
            to={'/favorites'}>
            Favorites
          </Link>
        }
        <Link
          activeClassName='projects-navigation-list__page-link--active'
          className='projects-navigation-list__page-link'
          to={'/projects/ethereum'}>
          More data about Ethereum
        </Link>
      </div>
      <HiddenElements>
        <Popup
          trigger={<span className='categories-button'><Button>Categories</Button></span>}
          on='click'
          position='bottom center'
        >
          <div className='categories-links'>
            {Object.entries(allMarketSegments).length > 0
              ? Object.entries(allMarketSegments).sort().map(([key, value]) =>
                <Checkbox
                  key={key}
                  id={key}
                  label={value || 'Unknown'}
                  onChange={handleSetCategory}
                  checked={categories[key]}
                />)
              : 'Categories not founded'
            }
            {Object.entries(allMarketSegments).length > 0 &&
              <Button
                className='clear-all-categories'
                content='Clear All'
                onClick={handleSetCategory}
                name='clearAllCategories'
              />}
          </div>
        </Popup>
      </HiddenElements>
    </div>
  )
}

export default ProjectsNavigation
