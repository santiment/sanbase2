import React from 'react'
import { connect } from 'react-redux'
import { Link } from 'react-router-dom'
import { compose, withState } from 'recompose'
import { Button, Label, Icon } from 'semantic-ui-react'
import AddNewAssetsListBtn from './AddNewAssetsListBtn'
import * as actions from './../../actions/types'
import './Watchlists.css'

const ConfigurationListBtn = ({ isConfigOpened = false, setConfigOpened }) => (
  <Button
    className='watchlists__config-btn'
    onClick={() => setConfigOpened(!isConfigOpened)}
    icon={isConfigOpened ? 'close' : 'setting'}
  />
)

// id is a number of current date for new list,
// until backend will have returned a real id
const isNewestList = id => typeof id === 'number'

export const hasAssetById = ({ id, listItems }) => {
  return listItems.some(item => item.project.id === id)
}

class Watchlists extends React.Component {
  render () {
    const {
      lists = [],
      isNavigation = false,
      projectId,
      slug,
      assetsListUI,
      addNewAssetList,
      isConfigOpened,
      setConfigOpened,
      removeAssetList
    } = this.props
    const Component = isNavigation ? Link : 'div'
    return (
      <div className='watchlists'>
        {lists.length > 0 && (
          <ConfigurationListBtn
            setConfigOpened={setConfigOpened}
            isConfigOpened={isConfigOpened}
          />
        )}
        <div className='watchlists__list'>
          {lists.length > 0 ? (
            lists.map(({ id, name, listItems = [] }) => (
              <Component
                key={id}
                className={'watchlists__item'}
                to={`/assets/list?name=${name}@${id}`}
                onClick={this.props.toggleAssetInList.bind(this, {
                  projectId,
                  assetsListId: id,
                  slug,
                  listItems
                })}
              >
                {isConfigOpened
                  ? !isNewestList(id) && (
                    <Icon
                      size='big'
                      onClick={removeAssetList.bind(this, id)}
                      name='trash'
                    />
                  )
                  : !isNavigation && (
                    <Icon
                      size='big'
                      name={
                        hasAssetById({
                          listItems,
                          id: projectId
                        })
                          ? 'check circle outline'
                          : 'circle outline'
                      }
                    />
                  )}
                <span>
                  {name}
                  {isNewestList(id) && (
                    <Label color='green' horizontal>
                      NEW
                    </Label>
                  )}
                </span>
              </Component>
            ))
          ) : (
            <div className='watchlists__empty-list-msg'>
              You don't have any watchlists yet.
            </div>
          )}
        </div>
        <AddNewAssetsListBtn
          assetsListUI={assetsListUI}
          addNewAssetList={addNewAssetList}
        />
      </div>
    )
  }
}

const mapStateToProps = state => {
  return {
    assetsListUI: state.assetsListUI
  }
}

const mapDispatchToProps = (dispatch, ownProps) => ({
  toggleAssetInList: ({ projectId, assetsListId, listItems, slug }) => {
    if (ownProps.isConfigOpened || !projectId) return
    const isAssetInList = hasAssetById({
      listItems: ownProps.lists.find(list => list.id === assetsListId)
        .listItems,
      id: projectId
    })
    if (isAssetInList) {
      return dispatch({
        type: actions.USER_REMOVE_ASSET_FROM_LIST,
        payload: { projectId, assetsListId, listItems, slug }
      })
    } else {
      return dispatch({
        type: actions.USER_ADD_ASSET_TO_LIST,
        payload: { projectId, assetsListId, listItems, slug }
      })
    }
  },
  addNewAssetList: payload =>
    dispatch({
      type: actions.USER_ADD_NEW_ASSET_LIST,
      payload
    }),
  removeAssetList: id =>
    dispatch({
      type: actions.USER_REMOVE_ASSET_LIST,
      payload: { id }
    }),
  chooseAssetList: (id, name) => {
    return dispatch({
      type: actions.USER_CHOOSE_ASSET_LIST,
      payload: { id, name }
    })
  }
})

export default compose(
  withState('isConfigOpened', 'setConfigOpened', false),
  connect(mapStateToProps, mapDispatchToProps)
)(Watchlists)
