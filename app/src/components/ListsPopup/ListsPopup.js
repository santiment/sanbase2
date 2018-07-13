import React from 'react'
import { Popup, Button } from 'semantic-ui-react'

const AddToListBtn = <Button basic color='purple'>add to list</Button>

const Lists = ({
  lists
}) => (
  <div>
    {lists.map(list => (
      list
    ))}
    <Button circular color='google plus' icon='plus' />
  </div>
)

const ListsPopup = ({ lists, trigger = AddToListBtn }) => {
  return (
    <Popup
      content={<Lists lists={lists} />}
      trigger={trigger}
      position='bottom center'
      on='click'
    />
  )
}

export default ListsPopup
