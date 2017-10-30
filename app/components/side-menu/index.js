import Link from 'next/link'
import Head from 'next/head'

export default (props) => (
    <div className="menu-list">
        <ul className="menu-content collapse out" id="menu-content">
            <li>
                <a href="#">
                    <i className="fa fa-home fa-md"></i>
                    Dashboard (tbd)
                </a>
            </li>
            <li data-toggle="collapse" data-target="#products" className="active">
                <a href="#" className="active">
                    <i className="fa fa-list fa-md"></i>
                    Data-feeds
                    <span className="arrow"></span>
                </a>
            </li>
            <ul className="sub-menu" id="products">
                <li>
                    <a href="#">Overview</a>
                </li>
                <li className="active">
                    <a href="#" className="active">
                        Cash Flow
                    </a>
                </li>
            </ul>
            <li>
                <a href="#">
                    <i className="fa fa-th fa-md"></i>
                    Signals
                </a>
            </li>
            <li>
                <a href="#">
                    <i className="fa fa-map fa-md"></i>
                    Roadmap
                </a>
            </li>
        </ul>
    </div>
)
