import Head from 'next/head'

export default (props) => (
  <Head>
    <meta charSet='utf-8' />
    <title>SANBase</title>
    <meta name='viewport' content='initial-scale=1.0, width=device-width, shrink-to-fit=no' />
    <link rel='shortcut icon' href='/static/cashflow/img/favicon.png' />
    <link rel='stylesheet' href='https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0-alpha.6/css/bootstrap.min.css' />
    <link href='https://fonts.googleapis.com/icon?family=Material+Icons' rel='stylesheet' />
    <link href='https://fonts.googleapis.com/css?family=Roboto:300,400,700' rel='stylesheet' />
    <script src='https://use.fontawesome.com/6f993f4769.js' />
    <link rel='stylesheet' href='//cdn.datatables.net/1.10.15/css/jquery.dataTables.min.css' />
    <link rel='stylesheet' href='/static/cashflow/css/style_dapp_mvp1.css' />
    <link rel='stylesheet' href='//cdnjs.cloudflare.com/ajax/libs/semantic-ui/2.2.12/semantic.min.css' />
    <script src='https://code.jquery.com/jquery-3.0.0.min.js' />
    <script src='https://cdnjs.cloudflare.com/ajax/libs/tether/1.4.0/js/tether.min.js' />
    <script src='https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0-alpha.6/js/bootstrap.min.js' />
    <script src='https://www.kryogenix.org/code/browser/sorttable/sorttable.js' />
    <script src='https://cdn.datatables.net/1.10.15/js/jquery.dataTables.min.js' />
    <script src='https://cdn.datatables.net/1.10.15/js/dataTables.bootstrap4.min.js' />
    {process.env.NODE_ENV === 'production' &&
    <script dangerouslySetInnerHTML={{ __html: `
      (function(i,s,o,g,r,a,m){i['GoogleAnalyticsObject']=r;i[r]=i[r]||function(){
              (i[r].q=i[r].q||[]).push(arguments)},i[r].l=1*new Date();a=s.createElement(o),
          m=s.getElementsByTagName(o)[0];a.async=1;a.src=g;m.parentNode.insertBefore(a,m)
      })(window,document,'script','https://www.google-analytics.com/analytics.js','ga');

      ga('create', 'UA-100571693-1', 'auto');
      ga('send', 'pageview');
    `}} />}
    { props.children }
  </Head>
)
