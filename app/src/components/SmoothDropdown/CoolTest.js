import React, { Component } from 'react'

export class CoolTest extends Component {
  render () {
    return (
      <header class='main-header'>
        <ul class='menu'>
          <li class='menu__item' data-sub='product'>
            <a href='#'>Product</a>
          </li>
          <li class='menu__item' data-sub='developer'>
            <a href='#'>Developer</a>
          </li>
          <li class='menu__item' data-sub='company'>
            <a href='#'>Company</a>
          </li>
        </ul>
        <div class='dd dropdown-holder'>
          <div class='dd__arrow dropdown__arrow' />
          <div class='dd__bg dropdown__bg'>
            <div class='dropdown__bg-bottom' />
          </div>

          <div class='dd__list dropdown__wrap'>
            <div class='dd__item dropdown-menu' id='product' data-sub='product'>
              <div class='dd__content dropdown-menu__content'>
                <div class='top-section'>
                  <div class='col-2'>
                    <ul>
                      <li>
                        <a href=''>
                          <h3>Payment</h3>
                          <p>
                            {' '}
                            Lorem ipsum dolor sit amet, consectetur adipisicing
                            elit.
                          </p>
                        </a>
                      </li>
                      <li>
                        <a href=''>
                          <h3>Connect</h3>
                          <p>
                            {' '}
                            consectetur adipisicing elit nesciunt! Assumenda,
                            adipisci.
                          </p>
                        </a>
                      </li>
                      <li>
                        <a href=''>
                          <h3>Atlas</h3>
                          <p>
                            {' '}
                            ipsum dolor sit amet, consectetur adipisicing elit.
                            .
                          </p>
                        </a>
                      </li>
                    </ul>
                    <ul>
                      <li>
                        <a href=''>
                          <h3>Subscription</h3>
                          <p> Lorem ipsum dolor sit amet, consectetur </p>
                        </a>
                      </li>
                      <li>
                        <a href=''>
                          <h3>Relay</h3>
                          <p>
                            {' '}
                            amet, consectetur adipisicing elit. Nisi, sequi!
                          </p>
                        </a>
                      </li>
                    </ul>
                  </div>
                </div>
                <div class='bottom-section'>
                  <ul>
                    <li>
                      <a href=''>Payment</a>
                    </li>
                    <li>
                      <a href=''>Connect</a>
                    </li>
                    <li>
                      <a href=''>Atlas</a>
                    </li>
                    <li>
                      <a href=''>Connect</a>
                    </li>
                    <li>
                      <a href=''>Atlas</a>
                    </li>
                  </ul>
                </div>
              </div>
            </div>
            <div
              class='dd__item dropdown-menu'
              id='developer'
              data-sub='developer'
            >
              <div class='dd__content dropdown-menu__content'>
                <div class='top-section'>
                  <div class='col-2'>
                    <div>
                      <h2 class='menu-title'>Front End</h2>
                      <ul>
                        <li>
                          <a href=''>Payment</a>
                        </li>
                        <li>
                          <a href=''>Connect</a>
                        </li>
                        <li>
                          <a href=''>Atlas</a>
                        </li>
                      </ul>
                    </div>
                    <div>
                      <h2 class='menu-title'>Back End</h2>
                      <ul>
                        <li>
                          <a href=''>Payment</a>
                        </li>
                        <li>
                          <a href=''>Connect</a>
                        </li>
                        <li>
                          <a href=''>Atlas</a>
                        </li>
                      </ul>
                    </div>
                  </div>
                </div>
                <div class='bottom-section info'>
                  <p>
                    Lorem ipsum dolor sit amet, consectetur adipisicing elit.
                    Odit totam officia molestias
                  </p>
                </div>
              </div>
            </div>
            <div class='dd__item dropdown-menu' data-sub='company'>
              <div class='dd__content dropdown-menu__content'>
                <div class='top-section'>
                  <ul>
                    <li>
                      <a href=''>Payment</a>
                    </li>
                    <li>
                      <a href=''>Connect</a>
                    </li>
                    <li>
                      <a href=''>Atlas</a>
                    </li>
                  </ul>
                </div>
                <div class='bottom-section'>
                  <ul>
                    <li>
                      <a href=''>Payment</a>
                    </li>
                    <li>
                      <a href=''>Connect</a>
                    </li>
                    <li>
                      <a href=''>Atlas</a>
                    </li>
                  </ul>
                </div>
              </div>
            </div>
          </div>
        </div>
      </header>
    )
  }
}

export default CoolTest
