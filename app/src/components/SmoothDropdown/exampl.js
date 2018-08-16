var ddTriggers = [].slice.call(document.querySelectorAll('.menu__item')),
  ddItems = [].slice.call(document.querySelectorAll('.dropdown-menu')),
  selectedMenu,
  ddBg = document.querySelector('.dropdown__bg'),
  ddBgBtm = document.querySelector('.dropdown__bg-bottom'),
  ddArrow = document.querySelector('.dropdown__arrow'),
  ddList = document.querySelector('.dropdown__wrap'),
  header = document.querySelector('.main-header'),
  closeDropdownTimeout,
  startCloseTimeout = function () {
    closeDropdownTimeout = setTimeout(() => closeDropdown(), 50)
  },
  stopCloseTimeout = function () {
    clearTimeout(closeDropdownTimeout)
  },
  openDropdown = function (el) {
    // - get menu ID
    var menuId = el.getAttribute('data-sub')
    // - get related sub menu
    var menuSub = document.querySelector(
      '.dropdown-menu[data-sub="' + menuId + '"]'
    )
    // - get menu sub content
    var menuSubCnt = menuSub.querySelector('.dropdown-menu__content')
    // - get bottom section of current sub
    var menuSubBtm = menuSubCnt
      .querySelector('.bottom-section')
      .getBoundingClientRect()
    // - get height of top section
    var menuSubTop = menuSubCnt
      .querySelector('.top-section')
      .getBoundingClientRect()
    // - get menu position
    var menuMeta = el.getBoundingClientRect()
    // - get sub menu position
    var subMeta = menuSubCnt.getBoundingClientRect()

    // - set selected menu
    selectedMenu = menuId

    // - Remove active Menu
    ddTriggers.forEach(el => el.classList.remove('active'))
    // - Set current menu to active
    el.classList.add('active')

    // - Remove active sub menu
    ddItems.forEach(el => el.classList.remove('active'))
    // - Set current menu to active
    menuSub.classList.add('active')

    // - Set dropdown menu background style to match current submenu style
    ddBg.style.opacity = 1
    ddBg.style.left =
      menuMeta.left - (subMeta.width / 2 - menuMeta.width / 2) + 'px'
    ddBg.style.width = subMeta.width + 'px'
    ddBg.style.height = subMeta.height + 'px'
    // - Set dropdown menu bottom section background position
    ddBgBtm.style.top = menuSubTop.height + 'px'
    console.log(menuSubBtm)

    // - Set Arrow position
    ddArrow.style.opacity = 1
    ddArrow.style.left = menuMeta.left + menuMeta.width / 2 - 10 + 'px'

    // - Set sub menu style
    ddList.style.opacity = 1
    ddList.style.left =
      menuMeta.left - (subMeta.width / 2 - menuMeta.width / 2) + 'px'
    ddList.style.width = subMeta.width + 'px'
    ddList.style.height = subMeta.height + 'px'

    // - Set current sub menu style
    menuSub.style.opacity = 1

    header.classList.add('dropdown-active')
  },
  /*
    openDropdown = (trigger) => {
      const {activeTrigger} = this.state

      const dropdown = dropdowns.get(trigger)
      const triggerMeta = trigger.getBoundingClientRect()
      const ddMeta = dropdown.getBoundingClientRect()

      activeTrigger.classList.remove('active')
      trigger.classList.add('active')
      this.setState(prev => ({activeTrigger: trigger}))

      dropdowns.get(activeTrigger).classList.remove('active')
      dropdown.classList.add(active)

      // UPDATE BG
      ddBg.style.opacity = 1
      ddBg.style.left =
        triggerMeta.left - (ddMeta.width / 2 - triggerMeta.width / 2) + 'px'
      ddBg.style.width = ddMeta.width + 'px'
      ddBg.style.height = ddMeta.height + 'px'
      // - Set dropdown menu bottom section background position
      ddBgBtm.style.top = menuSubTop.height + 'px'

       // - UPDATE DD_LIST
      ddList.style.opacity = 1
      ddList.style.left =
        triggerMeta.left - (ddMeta.width / 2 - triggerMeta.width / 2) + 'px'
      ddList.style.width = ddMeta.width + 'px'
      ddList.style.height = ddMeta.height + 'px'

      DD_WRAPPER.classList.add('dropdown-active')
    }

  */

  closeDropdown = function () {
    // - Remove active class from all menu items
    ddTriggers.forEach(el => el.classList.remove('active'))
    // - Remove active class from all sub menus
    ddItems.forEach(el => {
      el.classList.remove('active')
      el.style.opacity = 0
    })
    // - set sub menu background opacity
    ddBg.style.opacity = 0
    // - set arrow opacity
    ddArrow.style.opacity = 0

    // unset selected menu
    selectedMenu = undefined

    header.classList.remove('dropdown-active')
  }

/*
  closeDropdown = () => {
    const {activeTrigger} = this.state
    const activeDropdown = dropdowns.get(activeTrigger)

    activeTrigger.classList.remove('active')
    activeDropdown..classList.remove('active')
  }
*/

// - Binding mouse event to each menu items

ddTriggers.forEach(el => {
  // - mouse enter event
  el.addEventListener(
    'mouseenter',
    function () {
      stopCloseTimeout()
      openDropdown(this)
    },
    false
  )

  // - mouse leave event
  el.addEventListener('mouseleave', () => startCloseTimeout(), false)
})

/*
  trigger
  <
  onMouseEnter={() => {
    stopCloseTimeout()
    openDropdown(trigger)
  }}
  onMouseLeave={startCloseTimeout}
  />
*/

// - Binding mouse event to each sub menus
ddItems.forEach(el => {
  el.addEventListener('mouseenter', () => stopCloseTimeout(), false)
  el.addEventListener('mouseleave', () => startCloseTimeout(), false)
})
