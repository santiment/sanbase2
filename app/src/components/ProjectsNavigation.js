import React from 'react'
import { Link } from 'react-router-dom'
import {
  Button,
  Checkbox,
  Popup
} from 'semantic-ui-react'
import './ProjectsNavigation.css'

const ProjectsNavigation = ({
  path,
  categories,
  handleSetCategory,
  allMarketSegments,
  user
}) => {
  return (
    <div className='projects-navigation'>
      <h1>
        {path.includes('projects') && 'ERC20 Projects'}
        {path.includes('currencies') && 'Currencies'}
        {path.includes('favorites') && 'Favorites'}
      </h1>
      {(path.includes('currencies') || path.includes('favorites')) &&
        <span><Link to={'/projects'}>ERC20 Projects</Link></span>
      }
      {(path.includes('projects') || path.includes('favorites')) &&
        <span><Link to={'/currencies'}>Currencies</Link></span>
      }
      {user.account && !path.includes('favorites') &&
        <span><Link to={'/favorites'}>Favorites</Link></span>
      }
      <span><Link to={'/projects/ethereum'}>More data about Ethereum</Link></span>
      <Popup
        trigger={<span className='categories-button'><Button>Categories</Button></span>}
        on='click'
        position='bottom center'
      >
        <div className='categories-links'>
          {
            Object.entries(allMarketSegments).sort().map(([key, value]) =>
              <Checkbox
                key={key}
                id={key}
                label={value || 'Unknown'}
                onChange={handleSetCategory}
                checked={categories[key]}
              />
            )
          }
          <Button
            className='clear-all-categories'
            content='Clear All'
            onClick={handleSetCategory}
            name='clearAllCategories'
          />
        </div>
      </Popup>
    </div>
  )
}

export default ProjectsNavigation
