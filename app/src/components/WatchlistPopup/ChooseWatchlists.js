import React from 'react'
import cx from 'classnames'
import {
  createSkeletonProvider,
  createSkeletonElement
} from '@trainline/react-skeletor'
import { compose } from 'recompose'
import { Label, Icon, Popup } from 'semantic-ui-react'
import CreateWatchlistBtn from './CreateWatchlistBtn'
import styles from './Watchlists.module.css'

const DIV = createSkeletonElement('div', 'pending-header pending-div')

// id is a number of current date for new list,
// until backend will have returned a real id
const isNewestList = id => typeof id === 'number'

export const hasAssetById = ({ id, listItems }) => {
  return listItems.some(item => item.project.id === id)
}

const ChooseWatchlists = ({
  lists = [],
  isLoading,
  projectId,
  slug,
  watchlistUi,
  createWatchlist,
  removeAssetList,
  toggleAssetInList
}) => (
  <div className={styles.watchlists}>
    <div className={styles.list}>
      {lists.length > 0 ? (
        lists.map(({ id, name, listItems = [] }) => (
          <div
            key={id}
            className={styles.item}
            onClick={toggleAssetInList.bind(this, {
              projectId,
              assetsListId: id,
              slug,
              listItems
            })}
          >
            <DIV className={styles.name}>
              <div>{name}</div>
            </DIV>
            <div className={styles.tools}>
              {!isLoading && (
                <div className={styles.description}>
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
              <Popup
                inverted
                trigger={
                  <Icon
                    size='small'
                    className={cx({
                      [styles.included]: hasAssetById({
                        listItems,
                        id: projectId
                      })
                    })}
                    name={
                      hasAssetById({
                        listItems,
                        id: projectId
                      })
                        ? 'check square outline'
                        : 'square outline'
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
            </div>
          </div>
        ))
      ) : (
        <div className={styles.emptyListMsg}>
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
)(ChooseWatchlists)
