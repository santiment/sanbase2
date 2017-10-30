export default (props) => (
    <div className="row">
        <div className="col-12">
            <div className="panel">
                <div className="sortable">
                    <table id="projects" className="table table-condensed table=hover" cellSpacing="0" width="100%">
                        <thead>
                        <tr>
                            <th>Project</th>
                            <th title="also called an underscore">Market Cap</th>
                            <th>Balance (USD/ETH)</th>
                            <th>Last Outgoing TX</th>
                            <th>ETH Sent</th>
                        </tr>
                        </thead>
                        <tbody className='whaletable'>
                        <tr>
                            <td><img src="/static/cashflow/img/aeternity.png" /> Aeternity (AE)</td>
                            <td className="marketcap"></td>
                            <td className="address-link">
                                <div className="wallet">
                                    <div className="usd first">$0</div>
                                    <div className="eth"><a className="address" href="">Ξ0<i class="fa fa-external-link"></i></a></div>
                                </div>
                            </td>
                            <td>No transfers yet</td>
                            <td>0</td>
                        </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>
)
