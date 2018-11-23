import React from 'react'
import cx from 'classnames'
import {
  createSkeletonProvider,
  createSkeletonElement
} from '@trainline/react-skeletor'
import { Link } from 'react-router-dom'
import { compose } from 'recompose'
import { Label, Icon, Popup } from 'semantic-ui-react'
import qs from 'query-string'
import CreateWatchlistBtn from './CreateWatchlistBtn'
import './Watchlists.css'

const DIV = createSkeletonElement('div', 'pending-header pending-div')

// id is a number of current date for new list,
// until backend will have returned a real id
const isNewestList = id => typeof id === 'number'

export const hasAssetById = ({ id, listItems }) => {
  return listItems.some(item => item.project.id === id)
}

const updateSearchQuery = (searchParams, name, id) => {
  searchParams.name = `${name}@${id}`
  return searchParams
}

const Watchlists = ({
  lists = [],
  isNavigation = false,
  isLoading,
  projectId,
  slug,
  watchlistUi,
  createWatchlist,
  toggleAssetInList,
  toggleConfirmDeleteAssetList,
  searchParams
}) => (
  <div className='watchlists'>
    <div className='watchlists__list'>
      {lists.length > 0 ? (
        lists.map(({ id, name, listItems = [] }) => (
          <div key={id} className='watchlists__item'>
            <Link
              className='watchlists__item__link'
              to={{
                pathname: '/assets/list',
                search: qs.stringify(
                  updateSearchQuery(qs.parse(searchParams), name, id)
                )
              }}
            >
              <DIV className='watchlists__item__name'>
                <div>{name}</div>
              </DIV>
              {!isLoading && (
                <div className='watchlists__item__description'>
                  <Label>
                    {listItems.length > 0 ? listItems.length : 'empty'}
                  </Label>
                  {isNewestList(id) && (
                    <Label color='green' horizontal>
                      NEW
                    </Label>
                  )}
                </div>
              )}
            </Link>
            <div className='watchlists__tools'>
              {!isNavigation && (
                <Popup
                  inverted
                  trigger={
                    <Icon
                      size='big'
                      className={cx({
                        'icon-green': hasAssetById({
                          listItems,
                          id: projectId
                        })
                      })}
                      onClick={toggleAssetInList.bind(this, {
                        projectId,
                        assetsListId: id,
                        slug,
                        listItems
                      })}
                      name={
                        hasAssetById({
                          listItems,
                          id: projectId
                        })
                          ? 'check circle outline'
                          : 'add'
                      }
                    />
                  }
                  content={
                    hasAssetById({
                      listItems,
                      id: projectId
                    })
                      ? 'remove from list'
                      : 'add to list'
                  }
                  position='right center'
                  size='mini'
                />
              )}
              {!isNewestList(id) && (
                <Popup
                  inverted
                  trigger={
                    <Icon
                      size='large'
                      className='watchlists__tools__move-to-trash'
                      onClick={() => toggleConfirmDeleteAssetList(id)}
                      name='trash'
                    />
                  }
                  content='remove this list'
                  position='right center'
                  size='mini'
                />
              )}
            </div>
          </div>
        ))
      ) : (
        <div className='watchlists__empty-list-msg'>
          You don't have any watchlists yet.
        </div>
      )}
    </div>
    <CreateWatchlistBtn
      watchlistUi={watchlistUi}
      createWatchlist={createWatchlist}
    />
  </div>
)

export default compose(
  createSkeletonProvider(
    {
      lists: [
        {
          id: 1,
          name: '******',
          listItems: []
        },
        {
          id: 2,
          name: '******',
          listItems: []
        }
      ]
    },
    ({ isLoading }) => isLoading,
    () => ({
      backgroundColor: '#bdc3c7',
      color: '#bdc3c7'
    })
  )
)(Watchlists)
