/* eslint-disable */
import React from 'react'
import ReactDOM from 'react-dom'
import PropTypes from 'prop-types'
import styled from 'styled-components'
import debounce from 'lodash.debounce'

// Source: https://github.com/iamJoeTaylor/react-scrollable-list-view
// TODO: Fix source for new react

const ITEM_TYPES = {
  LIST_ITEM: 'LIST_ITEM',
  STICKY_ITEM: 'STICKY_ITEM'
}

const ITEM_TYPES_VALUES = Object.keys(ITEM_TYPES).map(type => ITEM_TYPES[type])

const getScrollTop = element => element.scrollTop

const isVariableHeight = item =>
  ITEM_TYPES_VALUES.indexOf(item.type.listViewComponentType) < 0 ||
  (ITEM_TYPES_VALUES.indexOf(item.type.listViewComponentType) >= 0 && !item.props.height)

const ListViewComponent = styled.div`
  position: absolute;
  top: 0;
  right: 0;
  bottom: 0;
  left: 0;
  overflow-y: scroll;
  overflow-x: hidden;
  opacity: ${({styledIsHidden}) => styledIsHidden ? '0' : '1'};
  -webkit-overflow-scrolling: touch;
`

const ListViewContentComponent = styled.div`
  position: absolute;
  top: 0;
  right: 0;
  bottom: 0;
  left: 0;
`

const ListViewRunwayComponent = styled.div`
  position: absolute;
  height: 1px;
  width: 1px;
  transform: ${({styledRunwayHeight}) => `translateY(${styledRunwayHeight}px)`};
`

export class ListView extends React.Component {
  constructor (props) {
    super(props)

    // internal this.props.children representation that includes height of dynamic cells
    this.items = {}
    this.stickyItems = []
    this.listViewBoundingBox = {}

    this.state = {
      pendingRequest: false,
      currentAnchorIndex: 0,
      lastAttachedItemIndex: 0,
      lastViewportItemIndex: 0,
      activeStickyItem: null
    }
  }

  setInitialState () {
    this.setState({
      pendingRequest: false,
      currentAnchorIndex: 0,
      lastAttachedItemIndex: 0
    })

    // Item at the top of frame
    this.anchorItem = { index: 0, offset: 0 }
    this.anchorScrollTop = 0

    this.hasVariableHeightCells = false
    if (window && this.onResizeHandler) {
      window.removeEventListener('resize', this.onResizeHandler)
      this.onResizeHandler = null
    }

    this.processInitialItems()
    this.calcuateViewportAndFill()
  }

  componentDidMount () {
    this.scroller.addEventListener('scroll', this.calcuateViewportAndFill.bind(this))
    this.debouncedRecalculate = debounce(this.recalculateOffset, 100, true).bind(this)

    this.setInitialState()

    if (!Number.isNaN(this.props.initialIndex)) {
      const child = this.props.children[this.props.initialIndex]
      if (!child) return

      const { key } = child
      const item = this.items[key]

      // If item is not registered yet use best guess
      const itemOffset = item ?
        item.offsetTop :
        this.props.aveCellHeight * this.props.initialIndex

      this.scroller.scrollTop = itemOffset + (this.headerOffset || 0)
    }
  }

  processInitialItems () {
    const { runwayItems, runwayItemsOpposite } = this.props
    const totalRunwayItems = (runwayItems || 0) + (runwayItemsOpposite || 0)
    for (let i = 0; i < totalRunwayItems; i++) {
      this.getItemHeight(i)
    }
  }

  needsMoreItems (lastScreenItem) {
    const loadMoreItem =
      this.props.children.length - this.props.loadMoreItemOffset + this.props.runwayItems - 1

    return this.props.hasMore &&
      loadMoreItem > 0 &&
      !this.state.pendingRequest &&
      this.state.lastViewportItemIndex < loadMoreItem &&
      lastScreenItem.index + this.props.runwayItems >= loadMoreItem
  }

  possiblyLoadMore (lastScreenItem) {
    if (this.needsMoreItems(lastScreenItem)) {
      const loadMorePromise = this.props.loadMore()
      if (loadMorePromise instanceof Promise) {
        this.setState({ pendingRequest: true })
        loadMorePromise.then(() => this.setState({ pendingRequest: false }))
      }
    }
  }

  calcuateViewportAndFill(e) {
    if (!this.scroller) return
    const scrollerScrollTop = getScrollTop(this.scroller)
    const scrollDelta = scrollerScrollTop - this.anchorScrollTop
    const isScrollUp = scrollDelta < 0

    // Special case, if we get to very top, always scroll to top.
    if (scrollerScrollTop === 0) {
      this.anchorItem = { index: 0, offset: 0 }
    } else {
      this.anchorItem = this.calculateAnchoredItem(this.anchorItem, scrollDelta)
    }

    this.anchorScrollTop = scrollerScrollTop;

    const lastScreenItem = this.calculateAnchoredItem(this.anchorItem, this.scroller.offsetHeight)
    if (isScrollUp) {
      e.preventDefault()
      this.fill(
        this.anchorItem.index,
        lastScreenItem.index + this.props.runwayItemsOpposite
      )
    } else {
      this.possiblyLoadMore(lastScreenItem);

      this.fill(
        this.anchorItem.index,
        lastScreenItem.index + this.props.runwayItems
      )
    }
  }

  attachResizeHandler() {
    if (!window || this.onResizeHandler) return
    this.onResizeHandler = this.onResize.bind(this)
    window.addEventListener('resize', this.onResizeHandler)
  }

  onResize() {
    // If we are dealing with sticky items, do a full calc
    if (this.stickyItems.length) return this.calcuateViewportAndFill()

    this.props.children.forEach((child, i) => {
      const item = this.items[child.key]
      if (item && item.calculated) {
        const { height, componentInstance } = item
        if (!componentInstance) return

        const newHeight = ReactDOM.findDOMNode(componentInstance)
          .getBoundingClientRect()
          .height

        item.height = newHeight
        if (height !== newHeight) this.debouncedRecalculate(i + 1)
      }
    })
  }

  // This will store the child in this.items if it doesn't exist there
  getItemHeight(index) {
    const child = this.props.children[index]
    if (!child) return 0

    const item = this.items[child.key]
    if (!item || item.index !== index) {
      // If we don't have a child at this index exit right away
      if (!child) return null
      if (!child.key) {
        // eslint-disable-next-line
        console.warn('ListView items should contain a unique key for stable results')
      }

      const height = child.props.height ?
        Number(child.props.height) :
        this.props.aveCellHeight

      const isSticky = child.type && child.type.listViewComponentType === ITEM_TYPES.STICKY_ITEM

      // Add this child to our internal refrence
      this.items[child.key] = {
        height,
        offsetTop: this.getOffsetFor(index),
        child,
        index,
        isSticky,
      }

      if (isSticky && this.stickyItems.filter(_item => _item.key === child.key).length === 0) {
        this.stickyItems.push({
          key: child.key,
          ...this.items[child.key],
        })
      }
    }

    return this.items[child.key].height
  }

  getOffsetFor(i) {
    if (i === 0) return 0

    const child = this.props.children[i - 1]
    if (!child) return 0

    const item = this.items[child.key]
    if (!item || typeof item.height === 'undefined') return 0

    return item.offsetTop + item.height
  }

  /**
   * Calculates the item that should be anchored after scrolling by delta from
   * the initial anchored item.
   * @param {{index: number, offset: number}} initialAnchor The initial position
   *     to scroll from before calculating the new anchor position.
   * @param {number} delta The offset from the initial item to scroll by.
   * @return {{index: number, offset: number}} Returns the new item and offset
   *     scroll should be anchored to.
   */
  calculateAnchoredItem(initialAnchor, delta) {
    if (delta === 0) return initialAnchor

    // Determine scroll direction based on unmutated delta
    const isScrollUp = delta < 0
    let i = initialAnchor.index

    delta += initialAnchor.offset

    /*
     * |--------|
     * |--------|
     * ......................
     * |--------| <--- i    |
     * |--------|           L viewport
     * |--------|           |
     * ......................
     * |--------|
     *
     */

    if (isScrollUp) {
      while (delta < 0 && i > 0) {
        const nextItemHeight = this.getItemHeight(i - 1) || this.props.aveCellHeight

        delta += nextItemHeight

        i--

        /*
         * This is a one time compinsation for the header in item 0's offset.
         * It is one time because this should only happen when it changes from index
         * 1 to index 0
         */
        if (i === 0 && !!this.props.header) delta += this.headerOffset || 0
      }
    } else {
      let shouldBreakLoop = false

      while (!shouldBreakLoop && delta > 0) {
        let nextItemHeight = this.getItemHeight(i) || this.props.aveCellHeight
        if (i === 0 && !!this.props.header) nextItemHeight += this.headerOffset || 0

        delta -= nextItemHeight

        if (delta <= 0) {
          /*
           * If scrolling down AND we are in the middle of the anchor item
           * continue to report this item and it's offset as the ancor item
           */
          delta += nextItemHeight
          shouldBreakLoop = true
        } else {
          /*
           * If we have MOAR scroll to go, continue the loop and check the
           * next item
           */
          i++
        }
      }
    }

    return {
      index: i,
      offset: delta,
    }
  }

  recalculateOffset(startingIndex = 0) {
    let i = startingIndex
    while (this.props.children[i]) {
      const item = this.items[this.props.children[i].key]
      if (item) {
        item.offsetTop = this.getOffsetFor(i)
        this.getItemHeight(i)
      }
      i++
    }

    this.forceUpdate()
  }

  fill(start, end) {
    const newState = {
      currentAnchorIndex: Math.max(0, start),
      lastViewportItemIndex: end,
      lastAttachedItemIndex: Math.max(end, this.props.runwayItems + this.props.runwayItemsOpposite),
    }

    if (this.stickyItems.length) {
      const stickyItems = this.stickyItems.slice().reverse()
      const activeStickyItems = stickyItems
        .filter(item => item.index <= newState.currentAnchorIndex)
      const activeStickyItem = activeStickyItems[0]
      if (activeStickyItem) {
        newState.activeStickyItem = activeStickyItem.index
      } else {
        newState.activeStickyItem = null
      }
    }

    this.setState(newState)
  }

  getRunwayHeight() {
    const currentItems = this.props.children

    // Optimistic runwayHeight
    let runwayHeight = this.props.aveCellHeight ?
      currentItems.length * this.props.aveCellHeight :
      0

    if (currentItems && currentItems.length) {
      const lastChildItem = currentItems[currentItems.length - 1]
      const lastChildOffset = (
        this.items[lastChildItem.key] && this.items[lastChildItem.key].offsetTop
      ) || 0
      runwayHeight = Math.max(
        lastChildOffset,
        runwayHeight
      )
    }

    return runwayHeight
  }

  getItems() {
    const {
      currentAnchorIndex,
      lastAttachedItemIndex,
      activeStickyItem,
    } = this.state

    const firstAttachedItem = Math.max(currentAnchorIndex - this.props.runwayItems, 0)
    const isStickyPrepended = activeStickyItem !== null && activeStickyItem < firstAttachedItem
    const children = this.props.children.slice(firstAttachedItem, lastAttachedItemIndex)

    if (isStickyPrepended) {
      children.unshift(this.props.children[activeStickyItem])
    }

    return children
      .map((item, i) => {
        const adjustedIndex = isStickyPrepended ?
          i - 1 :
          i
        const currentIndex = isStickyPrepended && i === 0 ?
          activeStickyItem :
          adjustedIndex + firstAttachedItem
        const previousChild = currentIndex !== 0 ?
          this.props.children[currentIndex - 1] :
          null
        const previousItem = previousChild ?
          this.items[previousChild.key] :
          null

        // Item isn't in memory yet, so put it there
        if (!this.items[item.key]) {
          if (currentIndex !== 0 &&
            typeof previousItem.index === 'number' &&
            previousItem.index !== currentIndex - 1
          ) {
            this.debouncedRecalculate(Math.min(previousItem.index, currentIndex))
          }
          this.getItemHeight(currentIndex)
        }

        // Make sure item is lined up where we think it should be
        if (
          this.items[item.key] && previousItem &&
          this.items[item.key].offsetTop &&
          previousItem.offsetTop + previousItem.height !== this.items[item.key].offsetTop
        ) {
          this.debouncedRecalculate(Math.min(previousItem.index, currentIndex))
        }

        const offsetTop = this.items[item.key].offsetTop

        // extra safe fallback
        if ((previousItem ? previousItem.offsetTop : 0) > offsetTop) {
          this.debouncedRecalculate(currentIndex - 1)
        }

        // If it is a variable height
        if (isVariableHeight(item)) {
          // Only add the resizeHandler when needed
          if (!this.hasVariableHeightCells) {
            this.hasVariableHeightCells = true
            this.attachResizeHandler()
          }

          // This will allow us to know when the child is rendered so we can
          // get it's height and store a ref to the current Component's instance
          // so on resize we can get it's height and reflow if needed
          item = React.cloneElement(item, {
            ref: (() => {
              const index = currentIndex
              const items = this.items
              const currentHeight = items[item.key].height

              return itemInstance => {
                if (!itemInstance) return

                const DOMNode = ReactDOM.findDOMNode(itemInstance)

                const newHeight = DOMNode.getBoundingClientRect().height

                this.items[item.key].height = newHeight
                this.items[item.key].calculated = true
                this.items[item.key].componentInstance = itemInstance

                // If height is different that first thought, reflow all below it
                if (currentHeight !== newHeight) this.debouncedRecalculate(index + 1)
              }
            })(),
          })
        }

        const style = {
          display: 'inline-block',
          width: '100%',
          position: 'absolute',
          transform: `translateY(${offsetTop}px)`, // Positions the items
        }

        const currentIsSticky = activeStickyItem === currentIndex && this.items[item.key].isSticky
        const anchorIsSticky = this.anchorItem.index === activeStickyItem
        const scrollIsInHeader = this.anchorItem.offset - this.headerOffset < 0
        const isStuck = currentIsSticky &&
          (
            // This makes sure if anchor is index 0 amke sure we are not in header to stick it
            !anchorIsSticky ||
            currentIndex !== 0 ||
            !this.props.header ||
            (!scrollIsInHeader && this.headerOffset)
          )

        if (isStuck) {
          style.position = 'fixed'
          style.transform = ''
          style.top = Math.max(this.listViewBoundingBoxInitialTop, 0)
          style.width = this.listViewBoundingBox.width
          style.zIndex = 9999
        }

        return (
          <span
            className={isStuck ? 'is-stuck' : ''}
            key={item.key}
            style={style}
            data-index={currentIndex}
          >{item}</span>
        )
      })
  }

  render() {
    const currentItems = this.getItems()
    const runwayHeight = this.getRunwayHeight()

    return (
      <ListViewComponent
        className="ListView"
        styledIsHidden={!Number.isNaN(this.props.initialIndex) && !this.scroller}
        innerRef={ref => {
          if (!ref) return
          this.scroller = ReactDOM.findDOMNode(ref)
        }}
        {...this.props}
      >
        <ListViewContentComponent
          className="ListView-content"
          innerRef={ref => {
            if (!ref) return
            // Need to capture stats on the ListView position so we can align items
            this.listViewBoundingBox = ReactDOM.findDOMNode(ref).getBoundingClientRect()
            if (!this.listViewBoundingBoxInitialTop) {
              this.listViewBoundingBoxInitialTop = this.listViewBoundingBox.top
            }
          }}
        >
          {
            this.props.header ?
              React.cloneElement(this.props.header, {
                ref: ref => {
                  if (!ref) return

                  const previousHeaderOffset = this.headerOffset
                  // We need to measure Header height
                  this.headerOffset = ReactDOM.findDOMNode(ref).getBoundingClientRect().height
                  if (previousHeaderOffset !== this.headerOffset) this.onResize()
                },
              }) :
              null
          }

          <ListViewRunwayComponent className="ListView-runway" styledRunwayHeight={runwayHeight}>
            {
              this.state.pendingRequest && this.props.loadingSpinner ?
                this.props.loadingSpinner :
                null
            }
          </ListViewRunwayComponent>

          {currentItems}
        </ListViewContentComponent>
      </ListViewComponent>
    )
  }
}
ListView.propTypes = {
  aveCellHeight: PropTypes.number,
  children: PropTypes.oneOfType([
    PropTypes.element,
    PropTypes.arrayOf(PropTypes.element),
  ]),
  // Has more Items to load?
  hasMore: PropTypes.bool,
  header: PropTypes.oneOfType([
    PropTypes.element,
    PropTypes.arrayOf(PropTypes.element),
  ]),
  loadingSpinner: PropTypes.oneOfType([
    PropTypes.element,
    PropTypes.arrayOf(PropTypes.element),
  ]),
  // Function called when scroll nears bottom
  // OPTIONAL: can return a promise to control request flow and show loading
  loadMore: PropTypes.func,
  // Number of items from the end of the list to call laodMore at
  loadMoreItemOffset: PropTypes.number,
  // Number of items to instantiate beyond current view in the scroll direction.
  runwayItems: PropTypes.number,
  // Number of items to instantiate beyond current view in the opposite direction.
  runwayItemsOpposite: PropTypes.number,
  // Index to start as anchor item
  initialIndex: PropTypes.number,
}

ListView.defaultProps = {
  children: [],
  runwayItems: 7,
  runwayItemsOpposite: 5,
  loadMore: () => {
    console.warn('List View `hasMore` content, but loadMore is not provided')
  },
  loadMoreItemOffset: 5,
  hasMore: false,
}

const createItemWithType = type => {
  class ItemShell extends React.Component {
    render() {
      return this.props.children
    }
  }
  ItemShell.listViewComponentType = type
  ItemShell.propTypes = {
    children: PropTypes.oneOfType([
      PropTypes.element,
      PropTypes.arrayOf(PropTypes.element),
    ]),
  }

  return ItemShell
}

export const ListViewItem = createItemWithType(ITEM_TYPES.LIST_ITEM)
export const ListViewStickyItem = createItemWithType(ITEM_TYPES.STICKY_ITEM)
