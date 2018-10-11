import React from 'react'
import { NavLink as Link } from 'react-router-dom'
import { Button, Checkbox, Popup } from 'semantic-ui-react'
import './ProjectsNavigation.css'
import { simpleSortStrings } from '../utils/sortMethods'

const HiddenElements = () => ''

const ProjectsNavigation = ({
  categories,
  handleSetCategory,
  marketSegments,
  user
}) => {
  return (
    <div className='projects-navigation'>
      <div className='projects-navigation-list'>
        <Link
          activeClassName='projects-navigation-list__page-link--active'
          className='projects-navigation-list__page-link'
          to={'/projects'}
          onClick={handleSetCategory}
          name='clearAllCategories'
        >
          ERC20 Projects
        </Link>
        <Link
          activeClassName='projects-navigation-list__page-link--active'
          className='projects-navigation-list__page-link'
          to={'/currencies'}
          onClick={handleSetCategory}
          name='clearAllCategories'
        >
          Currencies
        </Link>
        {user.token && (
          <Link
            activeClassName='projects-navigation-list__page-link--active'
            className='projects-navigation-list__page-link'
            to={'/favorites'}
            onClick={handleSetCategory}
            name='clearAllCategories'
          >
            Favorites
          </Link>
        )}
        <Link
          activeClassName='projects-navigation-list__page-link--active'
          className='projects-navigation-list__page-link'
          to={'/projects/ethereum'}
        >
          More data about Ethereum
        </Link>
      </div>
      <HiddenElements>
        <Popup
          trigger={
            <span className='categories-button'>
              <Button>Categories</Button>
            </span>
          }
          on='click'
          position='bottom center'
        >
          <div className='categories-links'>
            {marketSegments.length > 0
              ? [...marketSegments]
                .filter(marketSegment => marketSegment.count > 0)
                .sort((previous, next) =>
                  simpleSortStrings(previous.name, next.name)
                )
                .map(({ name, count }) => (
                  <Checkbox
                    key={name}
                    id={name}
                    label={`${name} (${count})`}
                    onChange={handleSetCategory}
                    checked={categories[name]}
                  />
                ))
              : 'Categories not founded'}
            {marketSegments.length > 0 && (
              <Button
                className='clear-all-categories'
                content='Clear All'
                onClick={handleSetCategory}
                name='clearAllCategories'
              />
            )}
          </div>
        </Popup>
      </HiddenElements>
    </div>
  )
}

export default ProjectsNavigation
