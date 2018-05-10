import React, { Fragment } from 'react'
import { Link } from 'react-router-dom'
import {
  Button,
  Checkbox,
  Popup
} from 'semantic-ui-react'
import './CashflowHead.css'

const CashflowHead = ({
  path,
  categories,
  handleSetCategory,
  allMarketSegments
}) => {
  return (
    <div className='cashflow-head'>
      {path.includes('projects') &&
        <Fragment>
          <h1>ERC20 Projects</h1>
          <span><Link to={'/currencies'}>Currencies</Link></span>
        </Fragment>
      }
      {path.includes('currencies') &&
        <Fragment>
          <h1>Currencies</h1>
          <span><Link to={'/projects'}>ERC20 Projects</Link></span>
        </Fragment>
      }
      <span><Link to={'/favorites'}>Favorites</Link></span>
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

export default CashflowHead
